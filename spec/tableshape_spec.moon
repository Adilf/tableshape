
{check_shape: check, :types} = require "tableshape"

deep_copy = (v) ->
  if type(v) == "table"
    {k, deep_copy(v) for k,v in pairs v}
  else
    v

test_examples = (t_fn, examples) ->
  for id, {:input, :expected, :fails} in ipairs examples
    it "repairs object #{id}", ->
      t = t_fn!

      clone = deep_copy input
      if fails
        assert.has_error ->
          out, fixed = t\repair input
      else
        out, fixed = t\repair input

        if expected
          assert.same true, fixed
          assert.same expected, out
        else
          assert.true out == input
          assert.same false, fixed

      -- the repair didn't mutate original table
      assert.same clone, input


describe "tableshape.is_type", ->
  it "detects type", ->
    import is_type, types from require "tableshape"
    assert.falsy is_type!
    assert.falsy is_type "hello"
    assert.falsy is_type {}
    assert.falsy is_type ->

    assert.truthy is_type types.string
    assert.truthy is_type types.shape {}
    assert.truthy is_type types.array_of { types.string}


describe "tableshape", ->
  basic_types = {
    {"any", valid: 1234}
    {"any", valid: "hello"}
    {"any", valid: ->}
    {"any", valid: true}
    {"any", valid: nil}

    {"number", valid: 1234, invalid: "hello"}
    {"function", valid: (->), invalid: {}}
    {"string", valid: "234", invalid: 777}
    {"boolean", valid: true, invalid: 24323}

    {"table", valid: { hi: "world" }, invalid: "{}"}
    {"array", valid: { 1,2,3,4 }, invalid: {hi: "yeah"}, check_errors: false}
    {"array", valid: {}, check_errors: false}

    {"integer", valid: 1234, invalid: 1.1}
    {"integer", valid: 0, invalid: "1243"}
  }

  for {type_name, :valid, :invalid, :check_errors} in *basic_types
    it "tests #{type_name}", ->
      t = types[type_name]

      assert.same {true}, {check valid, t}

      if invalid
        failure = {check invalid, t}
        if check_errors
          assert.same {nil, "got type #{type invalid}, expected #{type_name}"}, failure
        else
          assert.nil failure[1]

        failure = {check nil, t}
        if check_errors
          assert.same {nil, "got type nil, expected #{type_name}"}, failure
        else
          assert.nil failure[1]

      -- optional
      t = t\is_optional!
      assert.same {true}, {check valid, t}

      if invalid
        failure = {check invalid, t}
        if check_errors
          assert.same {nil, "got type #{type invalid}, expected #{type_name}"}, failure
        else
          assert.nil failure[1]

        assert.same {true}, {check nil, t}

  describe "one of", ->
    it "check value", ->
      ab = types.one_of {"a", "b"}

      assert.same nil, (ab "c")
      assert.same true, (ab "a")
      assert.same true, (ab "b")
      assert.same nil, (ab nil)

      more = types.one_of {true, 123}
      assert.same nil, (more "c")
      assert.same nil, (more false)
      assert.same nil, (more 124)
      assert.same true, (more 123)
      assert.same true, (more true)

    it "check value optional", ->
      ab = types.one_of {"a", "b"}
      ab_opt = ab\is_optional!

      assert.same nil, (ab_opt "c")
      assert.same true, (ab_opt "a")
      assert.same true, (ab_opt "b")
      assert.same true, (ab_opt nil)

    it "check value with sub types", ->
      -- with sub type checkers
      misc = types.one_of { "g", types.number, types.function }

      assert.same nil, (misc "c")
      assert.same true, (misc 2354)
      assert.same true, (misc ->)
      assert.same true, (misc "g")
      assert.same nil, (misc nil)

    it "renders error message", ->
      t = types.one_of {
        "a", "b"
        types.literal "MY THING", describe: => "(my thing)"
      }

      assert.same {
        nil
        "value `wow` does not match one of: `a`, `b`, (my thing)"
      }, {t "wow"}

    it "repairs with individual repair function", ->
      t = types.one_of {
        "okay"
        types.number\on_repair (val) -> tonumber val
      }

      assert.same {
        55, true
      }, {
        t\repair "55"
      }

      assert.same {
        "okay", false
      }, {
        t\repair "okay"
      }

    it "repairs with global repair function", ->
      t = types.one_of {
        "okay"
        types.number
      }, repair: (val) -> "nope"

      assert.same {
        "nope", true
      }, {
        t\repair "55"
      }

    it "repairs in order until success", ->
      k = ->

      t = types.one_of {
        types.number\on_repair (v) -> if v == "oops" then 5
        types.function\on_repair (v) -> k
      }

      assert.same {
        5, true
      }, {
        t\repair "oops"
      }

      assert.same {
        k, true
      }, {
        t\repair "well"
      }


  describe "all_of", ->
    it "checks value", ->
      t = types.all_of {
       types.string
       types.custom (k) -> k == "hello", "#{k} is not hello"
      }

      assert.same {nil, "zone is not hello"}, {t "zone"}
      assert.same {nil, "got type `number`, expected `string`"}, {t 5}

    it "repairs using global repair checker", ->
      t = types.all_of {
        types.string
      }, repair: (val) -> "okay"

      assert.same {"okay", true}, { t\repair 5 }
      assert.same {"sure", false}, { t\repair "sure" }

    it "user repair function of checker that fails", ->
      t = types.all_of {
        types.string
        types.custom(-> false)\on_repair (val) -> "fixed"
      }

      assert.same {"fixed", true}, { t\repair "wow" }

    it "fails to repair with no repair function", ->
      t = types.all_of {
        types.string
      }

      assert.has_error ->
        t\repair 5

    it "repairs with every function", ->
      t = types.all_of {
        types.table\on_repair (v) -> { v }
        types.shape {
          hello: "world"
        }, open: true, repair: (msg, field, value) -> "world"
      }

      assert.same {
        {
          "calzone"
          hello: "world"
        }
        true
      }, { t\repair "calzone" }

    it "repair short circuit", ->
      t = types.all_of {
        types.number\on_repair (v) -> tonumber v
        types.custom ((k) -> k >= 500), {
          repair: (v) -> math.max 500, v
        }
      }

      -- goes through
      assert.same {500, true}, { t\repair "5" }

      -- short circuits
      assert.same {nil, true}, { t\repair "five" }

  describe "shape", ->
    it "gets field errors, short_circuit", ->
      check = types.shape { color: "red" }
      assert.same "field `color` expected `red`, got `nil`", check\field_errors {}, true
      assert.same "expecting table", check\field_errors "blue", true
      assert.same "has extra field: `height`", check\field_errors { color: "red", height: 10 }, true
      assert.same nil, check\field_errors { color: "red" }, true

    it "gets field errors", ->
      check = types.shape { color: "red" }

      assert.same {
        "field `color` expected `red`, got `nil`"
        color: "expected `red`, got `nil`"
      }, check\field_errors {}, false

      assert.same {"expecting table"}, check\field_errors "blue"
      assert.same {"has extra field: `height`"}, check\field_errors { color: "red", height: 10 }
      assert.same {}, check\field_errors { color: "red" }

    it "checks value", ->
      check = types.shape { color: "red" }
      assert.same nil, (check color: "blue")
      assert.same true, (check color: "red")

      check = types.shape {
        color: types.one_of {"red", "blue"}
        weight: types.number
      }

      -- correct
      assert.same {true}, {
        check {
          color: "blue"
          weight: 234
        }
      }

      -- failed sub type
      assert.same nil, (
        check {
          color: "green"
          weight: 234
        }
      )

      -- missing data
      assert.same nil, (
        check {
          color: "green"
        }
      )

      -- extra data
      assert.same {true}, {
        check\is_open! {
          color: "red"
          weight: 9
          age: 3
        }
      }

      -- extra data
      assert.same nil, (
        check {
          color: "red"
          weight: 9
          age: 3
        }
      )

    it "checks value with literals", ->
      check = types.shape {
        color: "green"
        weight: 123
        ready: true
      }

      assert.same nil, (
        check {
          color: "greenz"
          weight: 123
          ready: true
        }
      )

      assert.same nil, (
        check {
          color: "greenz"
          weight: 125
          ready: true
        }
      )

      assert.same nil, (
        check {
          color: "greenz"
          weight: 125
          ready: false
        }
      )

      assert.same nil, (
        check {
          free: true
        }
      )

      assert.same true, (
        check {
          color: "green"
          weight: 123
          ready: true
        }
      )


  it "tests pattern", ->
    t = types.pattern "^hello"

    assert.same nil, (t 123)
    assert.same {true}, {t "hellowolr"}
    assert.same nil, (t "hell")

    t = types.pattern "^%d+$", coerce: true

    assert.same {true}, {t 123}
    assert.same {true}, {t "123"}
    assert.same nil, (t "2.5")


  it "tests map_of", ->
    stringmap = types.map_of types.string, types.string
    assert.same {true}, {stringmap {}}

    assert.same {true}, {stringmap {
      hello: "world"
    }}

    assert.same {true}, {stringmap {
      hello: "world"
      butt: "zone"
    }}

    assert.same {true}, {stringmap\is_optional! nil}
    assert.same nil, (stringmap nil)

    assert.same nil, (stringmap { hello: 5 })
    assert.same nil, (stringmap { "okay" })
    assert.same nil, (stringmap { -> })

    static = types.map_of "hello", "world"
    assert.same {true}, {static {}}
    assert.same {true}, {static { hello: "world" }}

    assert.same nil, (static { helloz: "world" })
    assert.same nil, (static { hello: "worldz" })

  it "tests array_of", ->
    numbers = types.array_of types.number

    assert.same {true}, {numbers {}}
    assert.same {true}, {numbers {1}}
    assert.same {true}, {numbers {1.5}}
    assert.same {true}, {numbers {1.5,2,3,4}}

    assert.same {true}, {numbers\is_optional! nil}
    assert.same nil, (numbers nil)

    hellos = types.array_of "hello"

    assert.same {true}, {hellos {}}
    assert.same {true}, {hellos {"hello"}}
    assert.same {true}, {hellos {"hello", "hello"}}

    assert.same nil, (hellos {"hello", "world"})

    shapes = types.array_of types.shape {
      color: types.one_of {"orange", "blue"}
    }

    assert.same {true}, {
      shapes {
        {color: "orange"}
        {color: "blue"}
        {color: "orange"}
      }
    }

    assert.same nil, (
      shapes {
        {color: "orange"}
        {color: "blue"}
        {color: "purple"}
      }
    )

    twothreefours = types.array_of 234

    assert.same {true}, {twothreefours {}}
    assert.same {true}, {twothreefours {234}}
    assert.same {true}, {twothreefours {234, 234}}
    assert.same nil, (twothreefours {"uh"})

  describe "literal", ->
    it "checks value", ->
      t = types.literal "hello world"

      assert.same {true}, {t "hello world"}
      assert.same {true}, {t\check_value "hello world"}

      assert.same {
        nil, "got `hello zone`, expected `hello world`"
      }, { t "hello zone" }

      assert.same {
        nil, "got `hello zone`, expected `hello world`"
      }, { t\check_value "hello zone" }

      assert.same {nil, "got `nil`, expected `hello world`"}, { t nil }
      assert.same {nil, "got `nil`, expected `hello world`"}, { t\check_value nil }

    it "checks value when optional", ->
      t = types.literal "hello world", optional: true
      assert.same {true}, { t nil }
      assert.same {true}, { t\check_value nil}

    it "repairs", ->
      t = types.literal "hello world", repair: (...) ->
        assert.same (...), "zone drone"
        "FIXED"

      assert.same {
        "FIXED"
        true
      }, {
        t\repair "zone drone"
      }

  describe "custom", ->
    it "checks value", ->
      check = types.custom (v) ->
        if v == 1
          true
        else
          nil, "v is not 1"

      assert.same {nil, "v is not 1"}, { check 2 }
      assert.same {nil, "v is not 1"}, { check\check_value 2 }

      assert.same {nil, "v is not 1"}, { check nil }
      assert.same {nil, "v is not 1"}, { check\check_value nil }

      assert.same {true}, { check 1 }
      assert.same {true}, { check\check_value 1 }

    it "checks with default error message", ->
      t = types.custom (n) -> n % 2 == 0

      assert.same {nil, "5 is invalid"}, {t 5}

    it "checks optional", ->
      check = types.custom(
        (v) ->
          if v == 1
            true
          else
            nil, "v is not 1"

        optional: true
      )

      assert.same {nil, "v is not 1"}, { check 2 }
      assert.same {nil, "v is not 1"}, { check\check_value 2 }

      assert.same {true}, { check nil }
      assert.same {true}, { check\check_value nil }

      assert.same {true}, { check 1 }
      assert.same {true}, { check\check_value 1 }

    describe "repair", ->
      check = types.custom(
        (v) ->
          if v == 1
            true
          else
            nil, "v is not 1"

        repair: (...) ->
          assert.same {"cool", "v is not 1"}, {...}
          "okay"
      )

      assert.same {"okay", true}, { check\repair "cool" }
      assert.same {1, false}, { check\repair 1 }

  describe "equivalent", ->
    it "checks value", ->
      assert.same true, (types.equivalent({}) {})
      assert.same true, (types.equivalent({1}) {1})
      assert.same true, (types.equivalent({hello: "world"}) {hello: "world"})
      assert.falsy (types.equivalent({hello: "world"}) {hello: "worlds"})

      check = types.equivalent {
        "great"
        color: {
          {}, {2}, { no: true}
        }
      }

      assert.same nil, (check\check_value "hello")
      assert.same nil, (check\check_value {})

      assert.same nil, (check\check_value {
        "great"
        color: {
          {}, {4}, { no: true}
        }
      })

      assert.same true, (check\check_value {
        "great"
        color: {
          {}, {2}, { no: true}
        }
      })

  describe "repair", ->
    it "doesn't repair basic type", ->
      assert.same {
        "hi", false
      }, {
        types.string\repair "hi", (val, err) -> tostring val
      }

    it "repairs a basic type", ->
      assert.same {
        "2334232", true
      }, {
        types.string\repair 2334232, (val, err) -> tostring val
      }

    it "repairs using repair option callback", ->
      int_string = types.pattern "^%d+$", {
        optional: true
        repair: (str) =>
          "0"
      }

      assert.same { "123", false }, { int_string\repair "123" }
      assert.same { "0", true }, { int_string\repair "what" }
      assert.same { nil, false }, { int_string\repair nil }

    it "repairs shape with repairable field", ->
      int_string = types.pattern "^%d+$", repair: (str, err) ->
        assert.same "zone", str
        assert.same "doesn't match pattern `^%d+$`", err
        "0"

      t = types.shape {
        hello: int_string
      }

      assert.same { {hello: "0"}, true }, { t\repair { hello: "zone" } }
      assert.same { {hello: "123"}, false }, { t\repair { hello: "123" } }

    it "repairs shape with shape's repair func on plain field", ->
      t = types.shape({
        hello: "world"
      })\on_repair (msg, key, val, err, expected_val) ->
        assert.same "field_invalid", msg
        assert.same "hello", key
        assert.same "zone", val
        assert.same "world", expected_val
        assert.same "field `hello` expected `world`, got `zone`", err
        "world"

      assert.same { { hello: "world" }, true }, { t\repair { hello: "zone" } }

    it "repairs shape with shape's repair function when type is wrong", ->
      t = types.shape({})\on_repair (msg, err, val) ->
        assert.same msg, "table_invalid"
        assert.same err, "expecting table"
        {cool: "yes"}

      assert.same {
        {cool: "yes"}
        true
      }, {t\repair "hello!"}

    it "repairs shape with shape's repair function when extra fields", ->
      t = types.shape({})\on_repair (msg, key, val) ->
        assert.same "extra_field", msg
        assert.same "color", key
        assert.same "blue", val
        nil

      assert.same {
        {}
        true
      }, {
        t\repair {
          color: "blue"
        }
      }

    it "repairs a copy of table, instead of mutating", ->
      to_repair = { hello: 888, cool: "pants" }
      copy = {k,v for k,v in pairs to_repair}

      t = types.shape {
        hello: types.string\on_repair => "butt"
        cool: types.string
      }

      out, changed = t\repair to_repair
      assert.same { cool: "pants", hello: "butt" }, out
      assert.same true, changed

      assert.false to_repair == out

      to_repair = {hello: "zone", cool: "zone"}
      out, changed = t\repair to_repair
      assert.false changed
      assert.same { cool: "zone", hello: "zone" }, out
      assert.true out == to_repair

    describe "shape repair", ->
      local t

      before_each ->
        number = types.number\on_repair (v) ->
          tonumber(v) or 0

        color = types.shape {
          r: number
          g: number
          b: number
        }

        t = types.shape {
          name: types.string\on_repair -> "unknown"
          id: types.number\is_optional!\on_repair -> nil
          color: color
          color2: color\is_optional!
        }

      test_examples (-> t), {
        -- fixes color, provies name
        {
          input: {
            color: {
              r: "cool"
              g: "123"
              b: 99
            }
          }

          expected: {
            name: "unknown"
            color: {
              r: 0
              g: 123
              b: 99
            }
          }
        }

        -- keeps okay id
        {
          input: {
            id: 234
            color: {}
          }

          expected: {
            id: 234
            name: "unknown"
            color: {r:0, g: 0, b: 0}
          }
        }

        -- strips bad id
        {
          input: {
            name: "bum zone"
            id: "freak"
            color: {}
          }

          expected: {
            name: "bum zone"
            color: {r:0, g: 0, b: 0}
          }
        }


        -- fixed bad color2
        {
          input: {
            name: "leaf"
            color: {r:1, g: 2, b: 3}
            color2: {}
          }

          expected: {
            name: "leaf"
            color: {r:1, g: 2, b: 3}
            color2: {r: 0, g: 0, b: 0}
          }
        }

        -- fails to fix field that can't repair itself
        {
          input: {
            name: "leaf"
            color: {r:1, g: 2, b: 3}
            color2: "hello world"
          }
          fails: true
        }

      }

    describe "array_of repair", ->
      it "uses array_of's handler for plain types", ->
        a = types.array_of("hello")\on_repair (msg, idx, v)->
          assert.same "field_invalid", msg
          return nil if idx == 2
          "hello-#{idx}-#{v}"

        assert.same {{
          "hello-1-9"
          "hello-3-7"
        }, true}, { a\repair {9,8,7} }

      local t
      before_each ->
        url_shape = types.pattern("^https?://")\on_repair (val) ->
          return nil unless type(val) == "string"
          "http://#{val}"

        t = types.array_of url_shape

      test_examples (-> t), {
        -- empty array
        { input: { } }

        -- fixes all
        {
          input: { "one", "two" }
          expected: { "http://one", "http://two" }
        }

        -- fixes some
        {
          input: { "leafo.net", "https://streak.club" }
          expected: { "http://leafo.net", "https://streak.club" }
        }

        -- nil replacements are stripped from array
        {
          input: {false, false, "leafo.net", true, 234, "https://itch.io" }
          expected: {"http://leafo.net", "https://itch.io"}
        }

        -- empties out bad array
        -- TODO: we should keep the hash items
        {
          input: {1,2,3, hello: "zone"}
          expected: {}
        }
      }


  describe "type switch", ->
    it "switches based type type", ->
      import type_switch from require "tableshape"

      k = switch type_switch(5)
        when types.string
          "no"
        when types.number
          "yes"

      assert.same k, "yes"

