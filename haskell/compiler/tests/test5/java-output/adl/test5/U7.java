package adl.test5;

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import org.adl.runtime.Factory;
import org.adl.runtime.JsonBinding;
import java.util.Map;
import java.util.Objects;

public class U7 {

  /* Members */

  private Disc disc;
  private Object value;

  /**
   * The U7 discriminator type.
   */
  public enum Disc {
    V
  }

  /* Constructors */

  public static U7 v(U3 v) {
    return new U7(Disc.V, Objects.requireNonNull(v));
  }

  public U7() {
    this.disc = Disc.V;
    this.value = U3.v((short)75);
  }

  public U7(U7 other) {
    this.disc = other.disc;
    switch (other.disc) {
      case V:
        this.value = U3.FACTORY.create((U3) other.value);
        break;
    }
  }

  private U7(Disc disc, Object value) {
    this.disc = disc;
    this.value = value;
  }

  /* Accessors */

  public Disc getDisc() {
    return disc;
  }

  public U3 getV() {
    if (disc == Disc.V) {
      return (U3) value;
    }
    throw new IllegalStateException();
  }

  /* Mutators */

  public void setV(U3 v) {
    this.value = Objects.requireNonNull(v);
    this.disc = Disc.V;
  }

  /* Object level helpers */

  @Override
  public boolean equals(Object other0) {
    if (!(other0 instanceof U7)) {
      return false;
    }
    U7 other = (U7) other0;
    return disc == other.disc && value.equals(other.value);
  }

  @Override
  public int hashCode() {
    return disc.hashCode() * 37 + value.hashCode();
  }

  /* Factory for construction of generic values */

  public static final Factory<U7> FACTORY = new Factory<U7>() {
    public U7 create() {
      return new U7();
    }
    public U7 create(U7 other) {
      return new U7(other);
    }
  };

  /* Json serialization */

  public static JsonBinding<U7> jsonBinding() {
    final JsonBinding<U3> v = U3.jsonBinding();
    final Factory<U7> _factory = FACTORY;

    return new JsonBinding<U7>() {
      public Factory<U7> factory() {
        return _factory;
      }

      public JsonElement toJson(U7 _value) {
        JsonObject _result = new JsonObject();
        switch (_value.getDisc()) {
          case V:
            _result.add("v", v.toJson(_value.getV()));
            break;
        }
        return _result;
      }

      public U7 fromJson(JsonElement _json) {
        JsonObject _obj = _json.getAsJsonObject();
        for (Map.Entry<String,JsonElement> _v : _obj.entrySet()) {
          if (_v.getKey().equals("v")) {
            return U7.v(v.fromJson(_v.getValue()));
          }
        }
        throw new IllegalStateException();
      }
    };
  }
}