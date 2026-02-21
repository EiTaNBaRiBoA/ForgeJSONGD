@abstract class_name ForgeJSONGDHelper extends ForgeJSONGDBase

#region Comparison

# Internal recursive function to perform the comparison.
static func compare_recursive(a: Variant, b: Variant) -> Dictionary:
	# If the types are different, they are not equal. Return the change.
	if typeof(a) != typeof(b):
		return {"old": a, "new": b}
	# Handle comparison based on the type of the variables.
	match typeof(a):
		TYPE_DICTIONARY:
			return _compare_dictionaries(a, b)
		TYPE_ARRAY:
			return _compare_arrays(a, b)
		_:
			# For all other primitive types (int, float, bool, string, null).
			if a != b:
				return {"old": a, "new": b}
			else:
				# They are identical, so there is no difference.
				return {}

# Compares two dictionaries.
static func _compare_dictionaries(a: Dictionary, b: Dictionary) -> Dictionary:
	var diff: Dictionary = {}
	var all_keys: Array = a.keys()
	for key in b:
		if not all_keys.has(key):
			all_keys.append(key)
	for key in all_keys:
		var key_in_a: bool = a.has(key)
		var key_in_b: bool = b.has(key)

		if key_in_a and not key_in_b:
			# Key was removed in 'b'.
			diff.set(key, {"old": a.get(key), "new": null})
		elif not key_in_a and key_in_b:
			# Key was added in 'b'.
			diff.set(key, {"old": null, "new": b.get(key)})
		else:
			# Key exists in both, so we recurse to compare their values.
			var result: Dictionary = compare_recursive(a.get(key), b.get(key))
			if not result.is_empty():
				# If the recursive comparison found a difference, add it to our diff report.
				diff.set(key, result)
	return diff


# Compares two arrays.
static func _compare_arrays(a: Array, b: Array) -> Dictionary:
	# This correctly handles nested structures within the arrays.
	if JSON.stringify(a) != JSON.stringify(b):
		return {"old": a, "new": b}
	# The arrays are identical.
	return {}
	
#endregion

#region Operation Helpers

## Recursively applies an operation to a variant. Dispatches to dictionary/array handlers.
static func apply_operation_recursively(base_var: Variant, ref_var: Variant, op_type: Operation) -> Variant:
	if ref_var is Dictionary and base_var is Dictionary:
		return _process_dictionary(base_var, ref_var, op_type)
	elif ref_var is Array and base_var is Array:
		return _process_array(base_var, ref_var, op_type)
	else:
		# Handle primitives or type mismatches
		return _process_primitive(base_var, ref_var, op_type)


## Handles the recursive operation logic for Dictionaries.
static func _process_dictionary(base_dict: Dictionary, ref_dict: Dictionary, op_type: Operation) -> Dictionary:
	for key in ref_dict:
		if key != SCRIPT_INHERITANCE:
			var ref_value = ref_dict[key]
			
			if base_dict.has(key):
				var base_value = base_dict.get(key)
				var result = apply_operation_recursively(base_value, ref_value, op_type)
				
				# For remove operations, a null result signifies deletion.
				if result == null and (op_type == Operation.Remove or op_type == Operation.RemoveValue):
					base_dict.erase(key)
				else:
					base_dict.set(key, result)
					
			# If the key doesn't exist in base, add it (for relevant operations).
			elif op_type == Operation.Add or op_type == Operation.AddDiffer or op_type == Operation.Replace:
				base_dict.set(key, ref_value)
				
	return base_dict


## Handles the recursive operation logic for Arrays.
static func _process_array(base_arr: Array, ref_arr: Array, op_type: Operation) -> Array:
	match op_type:
		Operation.Add, Operation.AddDiffer:
			for item in ref_arr:
				if not base_arr.has(item) || op_type == Operation.Add:
					base_arr.append(item)
			return base_arr
		
		Operation.Replace:
			# Replacing an array means returning the reference array.
			return ref_arr
			
		Operation.Remove, Operation.RemoveValue:
			# Filter the base array, keeping only items NOT in the reference array.
			var new_arr: Array = []
			for item in base_arr:
				if not ref_arr.has(item):
					new_arr.append(item)
			return new_arr
			
	return base_arr


## Handles the operation logic for primitive values.
static func _process_primitive(base_val: Variant, ref_val: Variant, op_type: Operation) -> Variant:
	match op_type:
		Operation.Add:
			return [base_val, ref_val]
		Operation.AddDiffer:
			return base_val if base_val == ref_val else [base_val, ref_val]
		Operation.Replace:
			return ref_val
		Operation.Remove:
			# A null return signals to the dictionary processor to erase the key.
			return null
		Operation.RemoveValue:
			return null if base_val == ref_val else base_val
	return base_val
#endregion
