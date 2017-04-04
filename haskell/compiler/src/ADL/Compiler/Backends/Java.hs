{-# LANGUAGE OverloadedStrings, FlexibleInstances #-}
module ADL.Compiler.Backends.Java(
  generate,
  JavaFlags(..),
  CodeGenProfile(..),
  defaultCodeGenProfile,
  javaPackage
  ) where

import qualified Data.ByteString.Base64 as B64
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map as Map
import qualified Data.Set as Set
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import qualified Text.Parsec as P

import qualified ADL.Adlc.Config.Java as JC
import qualified ADL.Compiler.ParserP as P

import Control.Monad
import Control.Monad.Trans
import Control.Monad.Trans.State.Strict
import qualified Data.Aeson as JSON
import Data.Char(toUpper)
import Data.Maybe(fromMaybe,isJust)
import Data.Foldable(for_,fold)
import Data.List(intersperse,replicate,sort)
import Data.Monoid
import Data.String(IsString(..))
import Data.Traversable(for)
import System.FilePath

import ADL.Compiler.AST
import ADL.Utils.IndentedCode
import ADL.Compiler.Backends.Java.Internal
import ADL.Compiler.Backends.Java.Parcelable
import ADL.Compiler.Backends.Java.Json
import ADL.Compiler.EIO
import ADL.Compiler.DataFiles
import ADL.Compiler.Primitive
import ADL.Compiler.Processing
import ADL.Compiler.Utils
import ADL.Core.Value
import ADL.Utils.FileDiff(dirContents)
import ADL.Utils.Format

generate :: AdlFlags -> JavaFlags -> FileWriter -> [FilePath] -> EIOT ()
generate af jf fileWriter modulePaths = catchAllExceptions  $ do
  let cgp = (jf_codeGenProfile jf)
  imports <- for modulePaths $ \modulePath -> do
    m <- loadAndCheckModule af modulePath
    generateModule jf fileWriter
                   (const cgp)
                   m
  when (jf_includeRuntime jf) $ liftIO $ do
    generateRuntime jf fileWriter (mconcat imports)

-- | Generate and write the java code for a single ADL module
-- The result value is the set of all java imports.
generateModule :: JavaFlags ->
                  FileWriter ->
                  (ScopedName -> CodeGenProfile) ->
                  RModule ->
                  EIO T.Text (Set.Set JavaClass)
generateModule jf fileWriter mCodeGetProfile m0 = do
  let moduleName = m_name m
      m = ( associateCustomTypes getCustomType moduleName
          . removeModuleTypedefs
          . expandModuleTypedefs
          ) m0
      decls = Map.elems (m_decls m)
      javaPackageFn mn = jf_package jf <> JavaPackage (unModuleName mn)

  checkCustomSerializations m
  
  imports <- for decls $ \decl -> do
    let codeProfile = mCodeGetProfile (ScopedName moduleName (d_name decl))
        maxLineLength = cgp_maxLineLength codeProfile
        klass  = javaClass (JavaPackage (unModuleName moduleName)) (d_name decl)
        filePath = javaClassFilePath (withPackagePrefix (jf_package jf) klass)
        generateType = case d_customType decl of
          Nothing -> True
          (Just ct) -> ct_generateType ct

    if generateType
      then do
        classFile <- case d_type decl of
          (Decl_Struct s) -> return (generateStruct codeProfile moduleName javaPackageFn decl s)
          (Decl_Union u)
            | isEnumeration u -> return (generateEnum codeProfile moduleName javaPackageFn decl u)
            | otherwise       -> return (generateUnion codeProfile moduleName javaPackageFn decl u)
          (Decl_Newtype n) -> return (generateNewtype codeProfile moduleName javaPackageFn decl n)
          (Decl_Typedef _) -> eioError "BUG: typedefs should have been eliminated"
        let lines = codeText maxLineLength (classFileCode classFile)
            imports = Set.fromList ([javaClass pkg cls| (cls,Just pkg) <- Map.toList (cf_imports classFile)])
        liftIO $ fileWriter filePath (LBS.fromStrict (T.encodeUtf8 (T.intercalate "\n" lines <> "\n")))
        return imports
      else do
        return mempty
  return (mconcat imports)

generateStruct :: CodeGenProfile -> ModuleName -> (ModuleName -> JavaPackage) -> CDecl -> Struct CResolvedType -> ClassFile
generateStruct codeProfile moduleName javaPackageFn decl struct =  execState gen state0
  where
    className = unreserveWord (d_name decl)
    state0 = classFile codeProfile moduleName javaPackageFn classDecl 
    isEmpty = null (s_fields struct)
    classDecl = "public class " <> className <> typeArgs
    typeArgs = case s_typeParams struct of
      [] -> ""
      args -> "<" <> commaSep (map unreserveWord args) <> ">"

    gen = do
      fieldDetails <- mapM genFieldDetails (s_fields struct)
      generateCoreStruct codeProfile moduleName javaPackageFn decl struct fieldDetails

      -- Json
      when (cgp_json codeProfile) $ do
        generateStructJson codeProfile decl struct fieldDetails

      -- Parcelable
      when (cgp_parcelable codeProfile) $ do
        generateStructParcelable codeProfile decl struct fieldDetails

generateNewtype :: CodeGenProfile -> ModuleName -> (ModuleName -> JavaPackage) -> CDecl -> Newtype CResolvedType -> ClassFile
generateNewtype codeProfile moduleName javaPackageFn decl newtype_ = execState gen state0
  where 
    className = unreserveWord (d_name decl)
    classDecl = "public class " <> className <> typeArgs
    state0 = classFile codeProfile moduleName javaPackageFn classDecl 
    typeArgs = case s_typeParams struct of
      [] -> ""
      args -> "<" <> commaSep (map unreserveWord args) <> ">"

    -- In java a newtype is just a single valued struct (with special serialisation)
    struct = Struct {
      s_typeParams = n_typeParams newtype_,
      s_fields =
        [ Field {
           f_name = "value",
           f_serializedName = "UNUSED",
           f_type = n_typeExpr newtype_,
           f_default = n_default newtype_,
           f_annotations = mempty
           }
        ]
      }

    gen = do
      fieldDetails <- mapM genFieldDetails (s_fields struct)
      generateCoreStruct codeProfile moduleName javaPackageFn decl struct fieldDetails

      -- Json
      when (cgp_json codeProfile) $ do
        generateNewtypeJson codeProfile decl newtype_ (fd_memberVarName (head fieldDetails))

      -- Parcelable
      when (cgp_parcelable codeProfile) $ do
        generateStructParcelable codeProfile decl struct fieldDetails

generateCoreStruct :: CodeGenProfile -> ModuleName -> (ModuleName -> JavaPackage)
                   -> CDecl -> Struct CResolvedType -> [FieldDetails] -> CState ()
generateCoreStruct codeProfile moduleName javaPackageFn decl struct fieldDetails =  gen
  where
    className = unreserveWord (d_name decl)
    state0 = classFile codeProfile moduleName javaPackageFn classDecl 
    isEmpty = null (s_fields struct)
    classDecl = "public class " <> className <> typeArgs
    typeArgs = case s_typeParams struct of
      [] -> ""
      args -> "<" <> commaSep (map unreserveWord args) <> ">"
    gen = do
      setDocString (generateDocString (d_annotations decl))

      preventImport className
      for_ fieldDetails (\fd -> preventImport (fd_memberVarName fd))
      for_ fieldDetails (\fd -> preventImport (fd_varName fd))
      
      objectsClass <- addImport "java.util.Objects"

      -- Fields
      for_ fieldDetails $ \fd -> do
        let modifiers =
             (if cgp_publicMembers codeProfile then ["public"] else ["private"])
             <>
             (if cgp_mutable codeProfile then [] else ["final"])
        addField (ctemplate "$1 $2 $3;" [T.intercalate " " modifiers,fd_typeExprStr fd,fd_memberVarName fd])

      -- Constructors
      let ctorArgs =  T.intercalate ", " [fd_typeExprStr fd <> " " <> fd_varName fd | fd <- fieldDetails]
          isGeneric = length (s_typeParams struct) > 0
          
          ctor1 =
            cblock (template "public $1($2)" [className,ctorArgs]) (
              clineN [
                if needsNullCheck fd
                  then template "this.$1 = $2.requireNonNull($3);" [fd_memberVarName fd, objectsClass, fd_varName fd]
                  else template "this.$1 = $2;" [fd_memberVarName fd, fd_varName fd]
                | fd <- fieldDetails]
            )

          ctor2 =
            cblock (template "public $1()" [className]) (
              clineN [template "this.$1 = $2;" [fd_memberVarName fd,fd_defValue fd] | fd <- fieldDetails]
            )

          ctor3 =
            cblock (template "public $1($2 other)" [className, className <> typeArgs]) (
              mconcat [ let n = fd_memberVarName fd in ctemplate "this.$1 = $2;" [n,fd_copy fd ("other." <>n)]
                      | fd <- fieldDetails ]
            )

      addMethod (cline "/* Constructors */")

      addMethod ctor1
      when (not isGeneric && not isEmpty) (addMethod ctor2)
      when (not isGeneric) (addMethod ctor3)

      -- Getters/Setters
      when (not isEmpty) (addMethod (cline "/* Accessors and mutators */"))
      
      when (not (cgp_publicMembers codeProfile)) $ do
        for_ fieldDetails $ \fd -> do
          let getter =
                cblock (template "public $1 $2()" [fd_typeExprStr fd,fd_accessorName fd]) (
                  ctemplate "return $1;" [fd_memberVarName fd]
                )
              setter =
                cblock (template "public void $1($2 $3)" [fd_mutatorName fd,fd_typeExprStr fd, fd_varName fd]) (
                  if needsNullCheck fd
                     then ctemplate "this.$1 = $2.requireNonNull($3);" [fd_memberVarName fd,objectsClass,fd_varName fd]
                     else ctemplate "this.$1 = $2;" [fd_memberVarName fd,fd_varName fd]
                )
          addMethod getter
          when (cgp_mutable codeProfile) (addMethod setter)

      -- equals and hashcode
      addMethod (cline "/* Object level helpers */")

      let equals = coverride "public boolean equals(Object other0)" (
            cblock (template "if (!(other0 instanceof $1))"  [className]) (
              cline "return false;"
              )
            <>
            ctemplate "$1 other = ($1) other0;" [className]
            <>
            cline "return"
            <>
            let terminators = replicate (length fieldDetails-1) " &&" <> [";"]
                tests = [cline (fd_equals fd (fd_memberVarName fd) ("other." <> fd_memberVarName fd) <> term)
                        | (fd,term) <- zip fieldDetails terminators]
            in  indent (mconcat tests)
            )
          equalsEmpty = coverride "public boolean equals(Object other)" (
            ctemplate "return other instanceof $1;" [className]
            )
      addMethod (if isEmpty then equalsEmpty else equals)

      addMethod $ coverride "public int hashCode()" (
        cline "int _result = 1;"
        <>
        mconcat [ctemplate "_result = _result * 37 + $1;" [fd_hashcode fd (fd_memberVarName fd)] | fd <- fieldDetails]
        <>
        cline "return _result;"
        )

      factoryInterface <- addImport (javaClass (cgp_runtimePackage codeProfile) "Factory")

      -- factory
      let factory =
            cblock1 (template "public static final $2<$1> FACTORY = new $2<$1>()" [className,factoryInterface]) (
              cblock (template "public $1 create()" [className]) (
                 ctemplate "return new $1();" [className]
              )
              <>
              cblock (template "public $1 create($1 other)" [className]) (
                 ctemplate "return new $1(other);" [className]
              )
            )

      let factoryg lazyC =
            cblock (template "public static $2 $3<$1$2> factory($4)" [className,typeArgs,factoryInterface,factoryArgs]) (
              cblock1 (template "return new $1<$2$3>()" [factoryInterface,className,typeArgs]) (
                mconcat [ctemplate "final $1<$2<$3>> $4 = new $1<>(() -> $5);"
                                   [lazyC,factoryInterface,fd_boxedTypeExprStr fd,fd_varName fd,fd_factoryExprStr fd]
                        | fd <- fieldDetails]
                <>
                cline ""
                <>
                cblock (template "public $1$2 create()" [className,typeArgs]) (
                   ctemplate "return new $1$2(" [className,typeArgs]
                   <>
                   indent (clineN (addTerminators "," "," ""  ctor1Args) <> cline ");")
                   )
                <>
                cline ""
                <>
                cblock (template "public $1$2 create($1$2 other)" [className,typeArgs]) (
                   ctemplate "return new $1$2(" [className,typeArgs]
                   <>
                   indent (clineN (addTerminators "," "," ""  ctor2Args) <> cline ");")
                   )
                )
              )

          factoryArgs = commaSep [template "$1<$2> $3" [factoryInterface,arg,factoryTypeArg arg] | arg <- s_typeParams struct]
          ctor1Args = [case f_default (fd_field fd) of
                        Nothing -> template "$1.get().create()" [fd_varName fd]
                        (Just _) -> fd_defValue fd
                      | fd <-fieldDetails]
          ctor2Args = [if immutableType (f_type (fd_field fd))
                       then template "other.$1" [fd_accessExpr fd]
                       else template "$1.get().create(other.$2)" [fd_varName fd,fd_accessExpr fd]
                      | fd <- fieldDetails]

      addMethod (cline "/* Factory for construction of generic values */")

      if isGeneric
        then do
          lazyC <- addImport (javaClass (cgp_runtimePackage codeProfile) "Lazy")
          addMethod (factoryg lazyC)
        else do
          addMethod factory

data UnionType = AllVoids | NoVoids | Mixed

generateUnion :: CodeGenProfile -> ModuleName -> (ModuleName -> JavaPackage) -> CDecl -> Union CResolvedType -> ClassFile
generateUnion codeProfile moduleName javaPackageFn decl union =  execState gen state0
  where
    className = unreserveWord (d_name decl)
    state0 = classFile codeProfile moduleName javaPackageFn classDecl
    classDecl = "public class " <> className <> typeArgs
    isGeneric = length (u_typeParams union) > 0
    discVar = if cgp_hungarianNaming codeProfile then "mDisc" else "disc"
    valueVar = if cgp_hungarianNaming codeProfile then "mValue" else "value"
    typeArgs = case u_typeParams union of
      [] -> ""
      args -> "<" <> commaSep (map unreserveWord args) <> ">"
    typecast fd from =
      if needsSuppressedCheckInCast (f_type (fd_field fd))
        then template "$1.<$2>cast($3)" [className,fd_boxedTypeExprStr fd,from]
        else template "($1) $2" [fd_boxedTypeExprStr fd,from]

    unionType = if and voidTypes then AllVoids else if or voidTypes then Mixed else NoVoids
      where
        voidTypes = [isVoidType (f_type f) | f <- u_fields union]
    
    gen = do
      setDocString (generateDocString (d_annotations decl))
      fieldDetails <- mapM genFieldDetails (u_fields union)
      fieldDetail0 <- case fieldDetails of
        [] -> error "BUG: unions with no fields are illegal"
        (fd:_) -> return fd

      preventImport className
      for_ fieldDetails (\fd -> preventImport (fd_memberVarName fd))
      for_ fieldDetails (\fd -> preventImport (fd_varName fd))
      preventImport discVar
      preventImport valueVar
        
      objectsClass <- addImport "java.util.Objects"

      -- Fields
      let modifiers = T.intercalate " " (["private"] <> if cgp_mutable codeProfile then [] else ["final"])
      addField (ctemplate "$1 Disc $2;" [modifiers,discVar])
      addField (ctemplate "$1 Object $2;" [modifiers,valueVar])

      -- Discriminator enum
      let terminators = replicate (length fieldDetails-1) "," <> [""]
          discdef =
            docStringComment (template "The $1 discriminator type." [className])
            <>
            cblock "public enum Disc" (
              mconcat [ctemplate "$1$2" [discriminatorName fd,term]
                      | (fd,term) <- zip fieldDetails terminators]
               )
      addMethod discdef

      -- constructors
      addMethod (cline "/* Constructors */")
      
      for_ fieldDetails $ \fd -> do
        let checkedv = if needsNullCheck fd then template "$1.requireNonNull(v)" [objectsClass] else "v"
            ctor = cblock (template "public static$1 $2$3 $4($5 v)" [leadSpace typeArgs, className, typeArgs, fd_unionCtorName fd, fd_typeExprStr fd]) (
              ctemplate "return new $1$2(Disc.$3, $4);" [className, typeArgs, discriminatorName fd, checkedv]
              )
            ctorvoid = cblock (template "public static$1 $2$3 $4()" [leadSpace typeArgs, className, typeArgs, fd_unionCtorName fd]) (
              ctemplate "return new $1$2(Disc.$3, null);" [className, typeArgs, discriminatorName fd]
              )

        addMethod (if isVoidType (f_type (fd_field fd)) then ctorvoid else ctor)

      let ctorPrivate = cblock (template "private $1(Disc disc, Object value)" [className]) (
            ctemplate "this.$1 = disc;" [discVar]
            <>
            ctemplate "this.$1 = value;" [valueVar]
            )

          ctorDefault = cblock (template "public $1()" [className]) (
            ctemplate "this.$1 = Disc.$2;" [discVar,discriminatorName fieldDetail0]
            <>
            ctemplate "this.$1 = $2;" [valueVar,fd_defValue fieldDetail0]
            )

          ctorCopy = cblock (template "public $1($1 other)" [className]) (
            ctemplate "this.$1 = other.$1;" [discVar]
            <>
            cblock (template "switch (other.$1)" [discVar]) (
              mconcat [
                ctemplate "case $1:" [discriminatorName fd]
                <>
                indent (
                  ctemplate "this.$1 = $2;" [valueVar,fd_copy fd (typecast fd ("other." <> valueVar))]
                  <>
                  cline "break;"
                  )
                | fd <- fieldDetails]
              )
            )

      when (not isGeneric) $ do
          addMethod ctorDefault
          addMethod ctorCopy
      addMethod $ ctorPrivate

      -- accessors
      addMethod (cline "/* Accessors */")

      addMethod $ cblock "public Disc getDisc()" (
        ctemplate "return $1;" [discVar]
        )

      for_ fieldDetails $ \fd -> do
        let getter = cblock (template "public $1 get$2()" [fd_typeExprStr fd, javaCapsFieldName (fd_field fd)]) (
              cblock (template "if ($1 == Disc.$2)" [discVar,discriminatorName fd]) (
                 ctemplate "return $1;" [typecast fd valueVar]
                 )
              <>
              cline "throw new IllegalStateException();"
              )

        when (not (isVoidType (f_type (fd_field fd)))) (addMethod getter)

      -- mutators
      addMethod (cline "/* Mutators */")

      when (cgp_mutable codeProfile) $ do 
        for_ fieldDetails $ \fd -> do
          let checkedv = if needsNullCheck fd then template "$1.requireNonNull(v)" [objectsClass] else "v"
              mtor = cblock (template "public void set$1($2 v)" [javaCapsFieldName (fd_field fd), fd_typeExprStr fd]) (
                ctemplate "this.$1 = $2;" [valueVar,checkedv]
                <>
                ctemplate "this.$1 = Disc.$2;" [discVar,discriminatorName fd]
                )
              mtorvoid = cblock (template "public void set$1()" [javaCapsFieldName (fd_field fd)]) (
                ctemplate "this.$1 = null;" [valueVar]
                <>
                ctemplate "this.$1 = Disc.$2;" [discVar,discriminatorName fd]
                )
          addMethod (if isVoidType (f_type (fd_field fd)) then mtorvoid else mtor)

      -- equals and hashcode
      addMethod (cline "/* Object level helpers */")

      addMethod $ coverride "public boolean equals(Object other0)" (
        cblock (template "if (!(other0 instanceof $1))"  [className]) (
          cline "return false;"
          )
        <>
        ctemplate "$1 other = ($1) other0;" [className]
        <>
        case unionType of
          NoVoids -> ctemplate "return $1 == other.$1 && $2.equals(other.$2);" [discVar,valueVar]
          AllVoids -> ctemplate "return $1 == other.$1;" [discVar]
          Mixed ->
            cblock (template "switch ($1)" [discVar]) (
              mconcat [
                ctemplate "case $1:" [discriminatorName fd]
                <>
                indent (
                  if isVoidType (f_type (fd_field fd))
                     then ctemplate "return $1 == other.$1;" [discVar]
                     else ctemplate "return $1 == other.$1 && $2.equals(other.$2);" [discVar,valueVar]
                  )
                | fd <- fieldDetails]
            )
            <>
            cline "throw new IllegalStateException();" 
       )

      addMethod $ coverride "public int hashCode()" (
        case unionType of
          NoVoids -> ctemplate "return $1.hashCode() * 37 + $2.hashCode();" [discVar,valueVar]
          AllVoids -> ctemplate "return $1.hashCode();" [discVar]
          Mixed ->
            cblock (template "switch ($1)" [discVar]) (
              mconcat [
                ctemplate "case $1:" [discriminatorName fd]
                <>
                indent (
                  if isVoidType (f_type (fd_field fd))
                     then ctemplate "return $1.hashCode();" [discVar]
                     else ctemplate "return $1.hashCode() * 37 + $2.hashCode();" [discVar,valueVar]
                  )
                | fd <- fieldDetails]
            )
            <>
            cline "throw new IllegalStateException();"
        )

      -- cast helper
      let needCastHelper = (or [needsSuppressedCheckInCast (f_type (fd_field fd))| fd <- fieldDetails])
      when needCastHelper $ addMethod (
        cline "@SuppressWarnings(\"unchecked\")"
        <>
        cblock "private static <T> T cast(final Object o)" (
          cline "return (T) o;"
          )
        )

      -- factory
      factoryInterface <- addImport (javaClass (cgp_runtimePackage codeProfile) "Factory")
      
      let factory =
            cblock1 (template "public static final $2<$1> FACTORY = new $2<$1>()" [className,factoryInterface]) (
              cblock (template "public $1 create()" [className]) (
                 ctemplate "return new $1();" [className]
              )
              <>
              cblock (template "public $1 create($1 other)" [className]) (
                 ctemplate "return new $1(other);" [className]
              )
            )

      let factoryg lazyC =
            cblock (template "public static$2 $3<$1$2> factory($4)" [className,leadSpace typeArgs,factoryInterface,factoryArgs]) (
              cblock1 (template "return new Factory<$1$2>()" [className,typeArgs]) (
                mconcat [ctemplate "final $1<Factory<$2>> $3 = new $1<>(() -> $4);"
                                   [lazyC,fd_boxedTypeExprStr fd,fd_varName fd,fd_factoryExprStr fd] | fd <- fieldDetails]
                <>
                cline ""
                <>
                cblock (template "public $1$2 create()" [className,typeArgs]) (
                  let val = case f_default (fd_field fieldDetail0) of
                        Nothing -> template "$1.get().create()" [fd_varName fieldDetail0]
                        (Just _) -> fd_defValue fieldDetail0
                  in ctemplate "return new $1$2(Disc.$3,$4);" [className,typeArgs,discriminatorName fieldDetail0,val]
                )
                <>
                cline ""
                <>
                cblock (template "public $1$2 create($1$2 other)" [className,typeArgs]) (
                  cblock (template "switch (other.$1)" [discVar]) (
                    mconcat [
                      ctemplate "case $1:" [discriminatorName fd]
                      <>
                      indent (
                        ctemplate "return new $1$2(other.$3,$4);"
                          [ className
                          , typeArgs
                          , discVar
                          , if immutableType (f_type (fd_field fd))
                              then template "other.$1" [valueVar]
                              else template "$1.get().create($2)" [fd_varName fd,typecast fd ("other." <>valueVar)]
                          ]
                        )
                      | fd <- fieldDetails]
                    )
                  <>
                  cline "throw new IllegalArgumentException();" 
                  )
                )
              )

          factoryArgs = commaSep [template "Factory<$1> $2" [arg,factoryTypeArg arg] | arg <- u_typeParams union]

      addMethod (cline "/* Factory for construction of generic values */")
      if isGeneric
        then do
          lazyC <- addImport (javaClass (cgp_runtimePackage codeProfile) "Lazy")
          addMethod (factoryg lazyC)
        else do
          addMethod factory

      -- Json
      when (cgp_json codeProfile) $ do
        generateUnionJson codeProfile decl union fieldDetails

      -- Parcelable
      when (cgp_parcelable codeProfile) $ do
        generateUnionParcelable codeProfile decl union fieldDetails

generateEnum :: CodeGenProfile -> ModuleName -> (ModuleName -> JavaPackage) -> CDecl -> Union CResolvedType -> ClassFile
generateEnum codeProfile moduleName javaPackageFn decl union = execState gen state0
  where
    className = unreserveWord (d_name decl)
    classDecl = "public enum " <> className
    state0 = classFile codeProfile moduleName javaPackageFn classDecl

    gen = do
      setDocString (generateDocString (d_annotations decl))
      fieldDetails <- mapM genFieldDetails (u_fields union)
      fieldDetail0 <- case fieldDetails of
        [] -> error "BUG: unions with no fields are illegal"
        (fd:_) -> return fd
      factoryInterface <- addImport (javaClass (cgp_runtimePackage codeProfile) "Factory")
      
      let terminators = replicate (length fieldDetails-1) "," <> [";"]
      mapM_ addField [ctemplate "$1$2" [discriminatorName fd,term] | (fd,term) <- zip fieldDetails terminators]

      addMethod $ coverride "public String toString()" (
        cblock "switch(this)" (
           mconcat [ctemplate "case $1: return \"$2\";" [discriminatorName fd, fd_serializedName fd] | fd <- fieldDetails]
           )
        <> cline "throw new IllegalArgumentException();"
        )
    
      addMethod $ cblock (template "public static $1 fromString(String s)" [className]) (
        mconcat [cblock (template "if (s.equals(\"$1\"))" [fd_serializedName fd]) (
                    ctemplate "return $1;" [discriminatorName fd]
                    )
                | fd <- fieldDetails ]
        <> cline "throw new IllegalArgumentException(\"illegal value: \" + s);"
        )

      addMethod $ cblock1 (template "public static final $2<$1> FACTORY = new $2<$1>()" [className,factoryInterface])
        (  cblock (template "public $1 create()" [className])
            ( ctemplate "return $1;" [discriminatorName fieldDetail0]
            )
        <> cline ""
        <> cblock (template "public $1 create($1 other)" [className])
            ( cline "return other;"
            )
        )

      -- Json
      when (cgp_json codeProfile) $ do
        generateEnumJson codeProfile decl union fieldDetails

      -- Parcelable
      when (cgp_parcelable codeProfile) $ do
        error "Unimplemented: Parcellable for enums"

generateRuntime :: JavaFlags -> FileWriter -> Set.Set JavaClass -> IO ()
generateRuntime jf fileWriter imports = do
    files <- dirContents runtimedir
    for_ files $ \inpath -> do
      let cls = javaClass rtpackage (T.pack (dropExtensions (takeFileName inpath)))
          toGenerate = imports <> Set.fromList
            [ javaClass rtpackage "ByteArray"
            , javaClass rtpackage "Factory"
            , javaClass rtpackage "Factories"
            ]
      when (Set.member cls toGenerate) $ do
        content <- LBS.readFile (runtimedir </> inpath)
        fileWriter (javaClassFilePath cls) (adjustContent content)
  where
    runtimedir =  javaRuntimeDir (jf_libDir jf)
    rtpackage = cgp_runtimePackage (jf_codeGenProfile jf)
    
    adjustContent :: LBS.ByteString -> LBS.ByteString
    adjustContent origLBS = LBS.fromStrict (T.encodeUtf8 newT)
      where origT = T.decodeUtf8 (LBS.toStrict origLBS)
            newT = T.replace "org.adl.runtime" (genJavaPackage rtpackage)
                 . T.replace "org.adl.sys" (genJavaPackage (jf_package jf <> javaPackage "sys"))
                 $ origT
      
