package adl.test5;

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import org.adl.runtime.Factory;
import org.adl.runtime.JsonBinding;
import java.util.Map;
import java.util.Objects;

public class U4 {

  /* Members */

  private Disc disc;
  private Object value;

  /**
   * The U4 discriminator type.
   */
  public enum Disc {
    V
  }

  /* Constructors */

  public static U4 v(S1 v) {
    return new U4(Disc.V, Objects.requireNonNull(v));
  }

  public U4() {
    this.disc = Disc.V;
    this.value = new S1();
  }

  public U4(U4 other) {
    this.disc = other.disc;
    switch (other.disc) {
      case V:
        this.value = S1.FACTORY.create((S1) other.value);
        break;
    }
  }

  private U4(Disc disc, Object value) {
    this.disc = disc;
    this.value = value;
  }

  /* Accessors */

  public Disc getDisc() {
    return disc;
  }

  public S1 getV() {
    if (disc == Disc.V) {
      return (S1) value;
    }
    throw new IllegalStateException();
  }

  /* Mutators */

  public void setV(S1 v) {
    this.value = Objects.requireNonNull(v);
    this.disc = Disc.V;
  }

  /* Object level helpers */

  @Override
  public boolean equals(Object other0) {
    if (!(other0 instanceof U4)) {
      return false;
    }
    U4 other = (U4) other0;
    return disc == other.disc && value.equals(other.value);
  }

  @Override
  public int hashCode() {
    return disc.hashCode() * 37 + value.hashCode();
  }

  /* Factory for construction of generic values */

  public static final Factory<U4> FACTORY = new Factory<U4>() {
    public U4 create() {
      return new U4();
    }
    public U4 create(U4 other) {
      return new U4(other);
    }
  };

  /* Json serialization */

  public static JsonBinding<U4> jsonBinding() {
    final JsonBinding<S1> v = S1.jsonBinding();
    final Factory<U4> _factory = FACTORY;

    return new JsonBinding<U4>() {
      public Factory<U4> factory() {
        return _factory;
      }

      public JsonElement toJson(U4 _value) {
        JsonObject _result = new JsonObject();
        switch (_value.getDisc()) {
          case V:
            _result.add("v", v.toJson(_value.getV()));
            break;
        }
        return _result;
      }

      public U4 fromJson(JsonElement _json) {
        JsonObject _obj = _json.getAsJsonObject();
        for (Map.Entry<String,JsonElement> _v : _obj.entrySet()) {
          if (_v.getKey().equals("v")) {
            return U4.v(v.fromJson(_v.getValue()));
          }
        }
        throw new IllegalStateException();
      }
    };
  }
}