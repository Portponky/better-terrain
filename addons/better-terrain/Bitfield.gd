class_name Bitfield

const INT_WIDTH = 32

static func set_bit(bf: Array[int], bit: int) -> void:
	var index = bit / INT_WIDTH
	while bf.size() <= index:
		bf.push_back(0)
	bf[index] |= 1 << (bit % INT_WIDTH)


static func clear_bit(bf: Array[int], bit: int) -> void:
	var index = bit / INT_WIDTH
	if bf.size() >= index:
		bf[index] &= ~(1 << (bit % INT_WIDTH))
		while !bf.is_empty() and bf.back() == 0:
			bf.pop_back()


static func test_bit(bf: Array[int], bit: int) -> bool:
	var index = bit / INT_WIDTH
	return bf.size() >= index and bf[index] & (1 << (bit % INT_WIDTH))


static func intersect(bf1: Array[int], bf2: Array[int]) -> bool:
	for i in min(bf1.size(), bf2.size()):
		if bf1[i] & bf2[i]:
			return true
	return false


static func to_int_array(bf: Array[int]) -> Array:
	var result : Array
	for i in bf.size() * INT_WIDTH:
		if bf[i / INT_WIDTH] & (1 << (i % INT_WIDTH)):
			result.push_back(i)
	return result


static func from_int_array(bits: Array) -> Array[int]:
	var result : Array[int]
	for b in bits:
		set_bit(result, b)
	return result

