extends RefCounted

## Validator for the test extension kind data_packs registers ("test_things", schema test.thing/1): the contract an
## owning lane's validator follows (ContentRegistry, "Extension kinds").


static func validate(_kind: String, entry: Dictionary, where: String) -> PackedStringArray:
	var errors := PackedStringArray()
	for key in entry:
		if not key in ["id", "size"]:
			errors.append("%s: unknown key \"%s\"" % [where, key])
	if not typeof(entry.get("size")) in [TYPE_INT, TYPE_FLOAT] or float(entry.get("size", 0)) <= 0.0:
		errors.append("%s: size must be a positive number" % where)
	return errors
