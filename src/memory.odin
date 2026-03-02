
package src

DEFAULT_MEM_ALIGN :: 8

import odinRuntime "base:runtime"

MemUnit :: enum u64 {
	Kilobyte = 1024,
	Megabyte = 1024 * 1024,
	Gigabyte = 1024 * 1024 * 1024,
	Terabyte = 1024 * 1024 * 1024 * 1024,
}

KILOBYTES :: #force_inline proc(Bytes: u64) -> u64 {
	return Bytes * u64(MemUnit.Kilobyte)
}
MEGABYTES :: #force_inline proc(Bytes: u64) -> u64 {
	return Bytes * u64(MemUnit.Megabyte)
}
GIGABYTES :: #force_inline proc(Bytes: u64) -> u64 {
	return Bytes * u64(MemUnit.Gigabyte)
}
TERABYTES :: #force_inline proc(Bytes: u64) -> u64 {
	return Bytes * u64(MemUnit.Terabyte)
}


MemoryArena :: struct {
	Size:              uintptr,
	Used:              uintptr,
	BasePointer:       rawptr,
	TempMemoryCounter: i32,
}

TempMemory :: struct {
	Arena:          ^MemoryArena,
	UsedOnCreation: uintptr,
}


InitializeArena :: proc(Arena: ^MemoryArena, Destination: ^u8, Size: uintptr) {
	Arena.Size = Size
	Arena.BasePointer = Destination
	Arena.Used = 0
	Arena.TempMemoryCounter = 0
}

GetArenaFreeSpace :: proc(Arena: ^MemoryArena) -> uintptr {
	return Arena.Size - Arena.Used
}

PushSize :: proc(
	Arena: ^MemoryArena,
	Size: uintptr,
	Alignment: uintptr = DEFAULT_MEM_ALIGN,
) -> rawptr {
	Size := Size
	destinationAdress: uintptr = cast(uintptr)Arena.BasePointer + Arena.Used
	memoryOffset: uintptr = 0
	alignmentMask := Alignment - 1
	if Alignment > 0 && (destinationAdress & alignmentMask) != 0 {
		memoryOffset = Alignment - (destinationAdress & alignmentMask)
	}
	Size += memoryOffset
	assert(Arena.Used + Size <= Arena.Size, "Blowing up arena capacity")

	result: rawptr = cast(rawptr)(destinationAdress + memoryOffset)
	Arena.Used += Size
	return result
}

PushStruct :: #force_inline proc(
	Arena: ^MemoryArena,
	$T: typeid,
	Alignment: uintptr = DEFAULT_MEM_ALIGN,
) -> ^T {
	return cast(^T)PushSize(Arena, size_of(T), Alignment)
}

PushMultipointer :: #force_inline proc(
	Arena: ^MemoryArena,
	$T: typeid,
	#any_int Count: int,
	Alignment: uintptr = DEFAULT_MEM_ALIGN,
) -> [^]T {
	return cast([^]T)PushSize(Arena, uintptr(size_of(T) * Count), Alignment)
}

PushSlice :: #force_inline proc(
	Arena: ^MemoryArena,
	$T: typeid/[]$E,
	#any_int Count: int,
	Alignment: uintptr = DEFAULT_MEM_ALIGN,
) -> T {
	mem := PushSize(Arena, uintptr(size_of(E) * Count), Alignment)
	rawSlice := odinRuntime.Raw_Slice{mem, Count}
	return transmute(T)rawSlice
}

CreateSubArena :: proc(Parent: ^MemoryArena, Child: ^MemoryArena, Size: uintptr) {
	Child.Size = Size
	Child.Used = 0
	Child.TempMemoryCounter = 0
	Child.BasePointer = PushSize(Parent, Size)
}

BeginTempMemory :: proc(Arena: ^MemoryArena) -> TempMemory {
	tempMem: TempMemory
	tempMem.Arena = Arena
	tempMem.UsedOnCreation = Arena.Used
	Arena.TempMemoryCounter += 1
	return tempMem
}

EndTempMemory :: proc(TempMem: ^TempMemory) {
	assert(TempMem.Arena.TempMemoryCounter > 0, "Trying to end temp memory but none is registered")
	assert(TempMem.Arena.Used >= TempMem.UsedOnCreation, "Memory was freed past the temp memory")
	TempMem.Arena.TempMemoryCounter -= 1
	TempMem.Arena.Used = TempMem.UsedOnCreation
}

ClearArena :: #force_inline proc(Arena: ^MemoryArena) {
	Arena.Used = 0
}

ValidateArena :: #force_inline proc(Arena: ^MemoryArena) {
	assert(Arena.TempMemoryCounter == 0, "Temp memory leak")
}
