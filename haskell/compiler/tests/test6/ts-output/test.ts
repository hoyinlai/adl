/* Automatically generated by adlc */

import * as ADL from './runtime/adl';
import * as sys_types from './sys/types';

export interface S {
  f_either: sys_types.Either<string, number>;
  f_error: sys_types.Error<number>;
  f_map: sys_types.Map<string, number>;
  f_mstring: sys_types.Maybe<string>;
  f_mstring2: sys_types.Maybe<string>;
  f_nstring: (string|null);
  f_nstring2: (string|null);
  f_pair: sys_types.Pair<number, number>;
  f_set: sys_types.Set<string>;
}

export function makeS(
  input: {
    f_either: sys_types.Either<string, number>,
    f_error: sys_types.Error<number>,
    f_map: sys_types.Map<string, number>,
    f_mstring: sys_types.Maybe<string>,
    f_mstring2?: sys_types.Maybe<string>,
    f_nstring: (string|null),
    f_nstring2?: (string|null),
    f_pair: sys_types.Pair<number, number>,
    f_set: sys_types.Set<string>,
  }
): S {
  return {
    f_either: input.f_either,
    f_error: input.f_error,
    f_map: input.f_map,
    f_mstring: input.f_mstring,
    f_mstring2: input.f_mstring2 === undefined ? {kind : just, value : 'sukpeepolup'} : input.f_mstring2,
    f_nstring: input.f_nstring,
    f_nstring2: input.f_nstring2 === undefined ? 'abcde' : input.f_nstring2,
    f_pair: input.f_pair,
    f_set: input.f_set,
  };
}

const S_AST : ADL.ScopedDecl =
  {"moduleName":"test","decl":{"annotations":[],"type_":{"kind":"struct_","value":{"typeParams":[],"fields":[{"annotations":[],"serializedName":"f_pair","default":{"kind":"nothing"},"name":"f_pair","typeExpr":{"typeRef":{"kind":"reference","value":{"moduleName":"sys.types","name":"Pair"}},"parameters":[{"typeRef":{"kind":"primitive","value":"Int32"},"parameters":[]},{"typeRef":{"kind":"primitive","value":"Double"},"parameters":[]}]}},{"annotations":[],"serializedName":"f_either","default":{"kind":"nothing"},"name":"f_either","typeExpr":{"typeRef":{"kind":"reference","value":{"moduleName":"sys.types","name":"Either"}},"parameters":[{"typeRef":{"kind":"primitive","value":"String"},"parameters":[]},{"typeRef":{"kind":"primitive","value":"Int32"},"parameters":[]}]}},{"annotations":[],"serializedName":"f_error","default":{"kind":"nothing"},"name":"f_error","typeExpr":{"typeRef":{"kind":"reference","value":{"moduleName":"sys.types","name":"Error"}},"parameters":[{"typeRef":{"kind":"primitive","value":"Int32"},"parameters":[]}]}},{"annotations":[],"serializedName":"f_map","default":{"kind":"nothing"},"name":"f_map","typeExpr":{"typeRef":{"kind":"reference","value":{"moduleName":"sys.types","name":"Map"}},"parameters":[{"typeRef":{"kind":"primitive","value":"String"},"parameters":[]},{"typeRef":{"kind":"primitive","value":"Double"},"parameters":[]}]}},{"annotations":[],"serializedName":"f_set","default":{"kind":"nothing"},"name":"f_set","typeExpr":{"typeRef":{"kind":"reference","value":{"moduleName":"sys.types","name":"Set"}},"parameters":[{"typeRef":{"kind":"primitive","value":"String"},"parameters":[]}]}},{"annotations":[],"serializedName":"f_mstring","default":{"kind":"nothing"},"name":"f_mstring","typeExpr":{"typeRef":{"kind":"reference","value":{"moduleName":"sys.types","name":"Maybe"}},"parameters":[{"typeRef":{"kind":"primitive","value":"String"},"parameters":[]}]}},{"annotations":[],"serializedName":"f_mstring2","default":{"kind":"just","value":{"kind":"object","value":[{"v1":"just","v2":{"kind":"string","value":"sukpeepolup"}}]}},"name":"f_mstring2","typeExpr":{"typeRef":{"kind":"reference","value":{"moduleName":"sys.types","name":"Maybe"}},"parameters":[{"typeRef":{"kind":"primitive","value":"String"},"parameters":[]}]}},{"annotations":[],"serializedName":"f_nstring","default":{"kind":"nothing"},"name":"f_nstring","typeExpr":{"typeRef":{"kind":"reference","value":{"moduleName":"sys.types","name":"Nullable"}},"parameters":[{"typeRef":{"kind":"primitive","value":"String"},"parameters":[]}]}},{"annotations":[],"serializedName":"f_nstring2","default":{"kind":"just","value":{"kind":"object","value":[{"v1":"just","v2":{"kind":"string","value":"abcde"}}]}},"name":"f_nstring2","typeExpr":{"typeRef":{"kind":"reference","value":{"moduleName":"sys.types","name":"Nullable"}},"parameters":[{"typeRef":{"kind":"primitive","value":"String"},"parameters":[]}]}}]}},"name":"S","version":{"kind":"nothing"}}};

export function texprS(): ADL.ATypeExpr<S> {
  return {value : {typeRef : {kind: "reference", value : {moduleName : "test",name : "S"}}, parameters : []}};
}

export const _AST_MAP = {
  "test.S" : S_AST
};
