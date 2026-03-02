package src

import "core:c"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import rand "core:math/rand"
import "core:os"
import win32 "core:sys/windows"
import "core:time"
import rl "vendor:raylib"


PRE_ALOCATED_MEM_MB :: 256
I32_MAX :: 2147483647

SCREEN_WIDTH :: 800
SCREEN_HEIGHT :: 450

INTERACTION_RADIUS :: 32
DYNAMIC_CIRCLE_RADIUS :: 6

MAX_DYNAMIC_BODIES :: 100000

TERRAIN_VERT :: #load("../res/terrainShaderVert.glsl", cstring)
TERRAIN_FRAG :: #load("../res/terrainShaderFrag.glsl", cstring)

CIRCLE_INSTANCING_VERT :: #load("../res/circleInstancedVert.glsl", cstring)
CIRCLE_INSTANCING_FRAG :: #load("../res/circleInstancedFrag.glsl", cstring)

Vector2 :: rl.Vector2

HeightMinMax :: struct {
	Min: int,
	Max: int,
}

CollisionColumn :: struct {
	Ranges: []HeightMinMax,
	Count:  i32,
}

Map :: struct {
	CollisionTileSize: int,
	CollisionColumns:  []CollisionColumn,
	BaseMapTexture:    rl.Texture2D,
	MaskRenderTexture: rl.RenderTexture2D,
	QuadMesh:          rl.Mesh,
	QuadModel:         rl.Model,
}

DynamicBody :: struct {
	Position: Vector2,
	Velocity: Vector2,
}

Simulation :: struct {
	DynamicCircles:      []DynamicBody,
	DynamicCirclesCount: i32,
}

MAX_PROFILING_SAMPLES :: 512
ProfilingSample :: struct {
	Milliseconds: [MAX_PROFILING_SAMPLES]f32,
}
ProfilingData :: struct {
	CurrentRecordingSample: i32,
	BallPhysics:            ProfilingSample,
	BallPhysicsCyclesAvg:   u64,
}

PerfCountFrequency: i64

main :: proc() {
	rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "DynamicTerrain")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)
	rl.SetExitKey(.BACKSPACE)

	perfCountFrequencyResult: win32.LARGE_INTEGER
	win32.QueryPerformanceFrequency(&perfCountFrequencyResult)
	PerfCountFrequency = cast(i64)perfCountFrequencyResult

	profiling: ProfilingData
	drawProfilingData: bool = true

	renderCollision: bool = false

	arena: MemoryArena
	mem := os.heap_alloc(int(MEGABYTES(PRE_ALOCATED_MEM_MB)))
	InitializeArena(&arena, cast(^u8)mem, uintptr(MEGABYTES(PRE_ALOCATED_MEM_MB)))

	sim: Simulation
	sim.DynamicCircles = PushSlice(&arena, []DynamicBody, MAX_DYNAMIC_BODIES)
	translationMatrices := PushSlice(&arena, []rl.Matrix, MAX_DYNAMIC_BODIES)

	circleMaterial, circleMesh := CreateCircleRenderingData()

	activeMap := GeneratePerlinMap(&arena)
	//activeMap := GenerateMapFromImageOnDisk(&arena, "res/wacky.png")


	textBuffer: [256]u8
	screenRect: Rect = {
		Min = {0, 0},
		Max = {SCREEN_WIDTH, SCREEN_HEIGHT},
	}

	for !rl.WindowShouldClose() {

		mouse := rl.GetMousePosition()

		if rl.IsMouseButtonPressed(.LEFT) {
			RemoveCircleFromMap(&activeMap, mouse, INTERACTION_RADIUS)
			SpawnMultipleDynamicCirclesArroundPoint(&sim, mouse, 10000)
		}

		if rl.IsKeyPressed(.TAB) {
			renderCollision = !renderCollision
		}
		if rl.IsKeyPressed(.P) {
			drawProfilingData = !drawProfilingData
		}

		rl.BeginDrawing()

		rl.ClearBackground(rl.DARKBLUE)

		if renderCollision {
			for i: i32 = 0; i < i32(len(activeMap.CollisionColumns)); i += 1 {
				column := &activeMap.CollisionColumns[i]
				for j: i32 = 0; j < column.Count; j += 1 {
					range := &column.Ranges[j]
					rl.DrawRectangle(
						i * i32(activeMap.CollisionTileSize),
						i32(range.Min * activeMap.CollisionTileSize),
						i32(activeMap.CollisionTileSize),
						i32((range.Max - range.Min) * activeMap.CollisionTileSize),
						rl.GRAY,
					)
				}
			}
		} else {
			rl.DrawModel(
				activeMap.QuadModel,
				{SCREEN_WIDTH / 2, SCREEN_HEIGHT / 2, 0},
				1,
				rl.WHITE,
			)
		}

		screenRectInflated: Rect = screenRect
		screenRectInflated.Min -= DYNAMIC_CIRCLE_RADIUS
		screenRectInflated.Max += DYNAMIC_CIRCLE_RADIUS

		profiling.BallPhysics.Milliseconds[profiling.CurrentRecordingSample] = 0
		profiling.BallPhysicsCyclesAvg = 0

		for i: i32 = sim.DynamicCirclesCount - 1; i >= 0; i -= 1 {
			dynCircle := &sim.DynamicCircles[i]
			dynCircle.Velocity += {0, 9.8}
			dynCircle.Position += dynCircle.Velocity * rl.GetFrameTime()

			if !RectContainsPoint(screenRectInflated, dynCircle.Position) {
				RemoveDynamicCircle(&sim, i)
			} else {
				clock := GetWallClock()
				cycleCountStart := CycleMeasureBegin()
				TickPhysicsDynamicCircle(dynCircle, &activeMap)
				profiling.BallPhysicsCyclesAvg += CycleMeasureEnd(cycleCountStart)
				ms := GetElapsedMiliSeconds(clock, GetWallClock())
				profiling.BallPhysics.Milliseconds[profiling.CurrentRecordingSample] += ms

				translationMatrices[i] = rl.MatrixTranslate(
					dynCircle.Position.x,
					dynCircle.Position.y,
					0,
				)
			}
		}

		rl.DrawMeshInstanced(
			circleMesh,
			circleMaterial,
			&translationMatrices[0],
			sim.DynamicCirclesCount,
		)

		if sim.DynamicCirclesCount > 0 {
			profiling.BallPhysicsCyclesAvg /= u64(sim.DynamicCirclesCount)
		}

		//DrawCircleIntersectionTest(mouse)
		//DrawCollisionTest(mouse)

		rl.DrawCircleLines(i32(mouse.x), i32(mouse.y), INTERACTION_RADIUS, rl.RED)

		rl.DrawFPS(10, 10)

		outStrLen := len(fmt.bprintf(textBuffer[:], "Dynamic Bodies: %d", sim.DynamicCirclesCount))
		textBuffer[outStrLen] = 0
		rl.DrawText(cstring(&textBuffer[0]), 10, 40, 14, rl.WHITE)

		outStrLen = len(
			fmt.bprintf(
				textBuffer[:],
				"Cycles x %d: %d",
				sim.DynamicCirclesCount,
				profiling.BallPhysicsCyclesAvg,
			),
		)
		textBuffer[outStrLen] = 0
		rl.DrawText(cstring(&textBuffer[0]), 10, 60, 14, rl.WHITE)

		if drawProfilingData {
			DrawProfilingData(&profiling, SCREEN_HEIGHT - 140)
		}

		rl.EndDrawing()

		profiling.CurrentRecordingSample =
			(profiling.CurrentRecordingSample + 1) % MAX_PROFILING_SAMPLES
	}
}

DrawCircleIntersectionTest :: proc(Mouse: Vector2) {
	rl.DrawCircleLines(SCREEN_WIDTH / 2, SCREEN_HEIGHT / 2, 64, rl.WHITE)
	if math.abs(Mouse.x - (SCREEN_WIDTH / 2)) <= 64 {
		intertsectionRef := AxisAlignedLine_Circle_Intersection(Mouse.x - (SCREEN_WIDTH / 2), 64)
		pointA: rl.Vector2 = {Mouse.x, (SCREEN_HEIGHT / 2) + intertsectionRef}
		pointB: rl.Vector2 = {Mouse.x, (SCREEN_HEIGHT / 2) - intertsectionRef}
		rl.DrawCircle(i32(pointA.x), i32(pointA.y), 8, rl.RED)
		rl.DrawCircle(i32(pointB.x), i32(pointB.y), 8, rl.RED)
	}
	rl.DrawLine(i32(Mouse.x), 0, i32(Mouse.x), SCREEN_HEIGHT, rl.YELLOW)
}

DrawCollisionTest :: proc(Mouse: Vector2) {
	r: Rect = {
		Min = {400, 100},
		Max = {420, 300},
	}
	size := r.Max - r.Min
	ok, info := CircleRectCollision(Mouse, INTERACTION_RADIUS, r)

	rl.DrawRectangleLines(i32(r.Min.x), i32(r.Min.y), i32(size.x), i32(size.y), rl.WHITE)
	if ok {
		rl.DrawCircle(i32(info.Point.x), i32(info.Point.y), 3, rl.RED)
		dir: Vector2

		if info.PenetrationDistance < INTERACTION_RADIUS {
			dir = linalg.vector_normalize(info.Point - Mouse) * info.PenetrationDistance
		} else {
			dir = {0, Mouse.y - r.Min.y + INTERACTION_RADIUS}
		}

		rl.DrawLine(
			i32(info.Point.x),
			i32(info.Point.y),
			i32(info.Point.x + dir.x),
			i32(info.Point.y + dir.y),
			rl.GREEN,
		)
		rl.DrawCircleLines(
			i32(Mouse.x - dir.x),
			i32(Mouse.y - dir.y),
			INTERACTION_RADIUS,
			rl.GREEN,
		)
	}
}

CreateCircleRenderingData :: proc() -> (rl.Material, rl.Mesh) {
	circleShader: rl.Shader = rl.LoadShaderFromMemory(
		CIRCLE_INSTANCING_VERT,
		CIRCLE_INSTANCING_FRAG,
	)

	circleShader.locs[rl.ShaderLocationIndex.MATRIX_MODEL] = rl.GetShaderLocationAttrib(
		circleShader,
		"instanceTransform",
	)

	circleMaterial: rl.Material = rl.LoadMaterialDefault()
	circleMaterial.shader = circleShader
	circleMesh := rl.GenMeshPlane(DYNAMIC_CIRCLE_RADIUS * 2, DYNAMIC_CIRCLE_RADIUS * 2, 1, 1)

	return circleMaterial, circleMesh
}

SpawnMultipleDynamicCirclesArroundPoint :: proc(Sim: ^Simulation, Point: Vector2, Amount: int) {
	toSpawn := Amount
	toSpawn = math.min(toSpawn, MAX_DYNAMIC_BODIES - int(Sim.DynamicCirclesCount))

	for i := 0; i < toSpawn; i += 1 {
		positionOffset: Vector2 = {
			rand.float32_range(-INTERACTION_RADIUS, INTERACTION_RADIUS) / 2,
			rand.float32_range(-INTERACTION_RADIUS, INTERACTION_RADIUS) / 2,
		}
		SpawnDynamicCircle(
			Sim,
			Point + positionOffset,
			{rand.float32_range(-50, 50), rand.float32_range(-150, -80)},
		)
	}
}

SpawnDynamicCircle :: proc(Sim: ^Simulation, Position: Vector2, InitialVelocity: Vector2) {
	assert(int(Sim.DynamicCirclesCount) < len(Sim.DynamicCircles))
	newCircle := &Sim.DynamicCircles[Sim.DynamicCirclesCount]
	newCircle.Position = Position
	newCircle.Velocity = InitialVelocity
	Sim.DynamicCirclesCount += 1
}

RemoveDynamicCircle :: proc(Sim: ^Simulation, Index: i32) {
	last := &Sim.DynamicCircles[Sim.DynamicCirclesCount - 1]
	Sim.DynamicCircles[Index] = last^
	Sim.DynamicCirclesCount -= 1
}

GenerateMapFromImage :: proc(Arena: ^MemoryArena, Image: ^rl.Image) -> Map {
	m: Map = {}

	m.CollisionTileSize = 2
	amountOfColumns: int = SCREEN_WIDTH / int(m.CollisionTileSize)

	m.CollisionColumns = PushSlice(Arena, []CollisionColumn, amountOfColumns)

	m.BaseMapTexture = rl.LoadTextureFromImage(Image^)

	collisionImage: rl.Image = rl.ImageCopy(Image^)
	defer rl.UnloadImage(collisionImage)

	collisionHeight: i32 = i32(amountOfColumns)
	collisionWidth: i32 = SCREEN_HEIGHT / i32(m.CollisionTileSize)
	rl.ImageResize(&collisionImage, collisionWidth, collisionHeight)

	shader := rl.LoadShaderFromMemory(TERRAIN_VERT, TERRAIN_FRAG)
	mainTexLoc := rl.GetShaderLocation(shader, "mainTex")
	rl.SetShaderValueTexture(shader, mainTexLoc, m.BaseMapTexture)

	m.MaskRenderTexture = rl.LoadRenderTexture(SCREEN_HEIGHT, SCREEN_WIDTH)
	maskTexLoc := rl.GetShaderLocation(shader, "maskTex")
	rl.SetShaderValueTexture(shader, maskTexLoc, m.MaskRenderTexture.texture)


	m.QuadMesh = rl.GenMeshPlane(SCREEN_WIDTH, SCREEN_HEIGHT, 1, 1)

	m.QuadModel = rl.LoadModelFromMesh(m.QuadMesh)
	m.QuadModel.materials[0].shader = shader


	data: [^]rl.Color = cast([^]rl.Color)collisionImage.data

	for i := 0; i < amountOfColumns; i += 1 {
		curColumn := &m.CollisionColumns[i]
		curColumn.Ranges = PushSlice(
			Arena,
			[]HeightMinMax,
			(SCREEN_HEIGHT / m.CollisionTileSize) / 2,
		)
		curColumn.Count = 0

		wasFilled := false
		for p := 0; p < int(collisionWidth); p += 1 {
			sample := f32(data[i * int(collisionWidth) + p].r) / 255.0
			filled := sample >= 0.5
			if filled != wasFilled {
				if filled {
					curColumn.Ranges[curColumn.Count].Min = p
				} else {
					curColumn.Ranges[curColumn.Count].Max = (p - 1)
					curColumn.Count += 1
				}
				wasFilled = filled
			}
		}
		if wasFilled {
			curColumn.Ranges[curColumn.Count].Max = (int(collisionWidth))
			curColumn.Count += 1
		}
	}

	return m
}

GeneratePerlinMap :: proc(Arena: ^MemoryArena) -> Map {
	//image width and height are reversed so we can iterate by line
	//marginal perf gain since images are small and it happens once, but whatever, its done
	perlinHeight: i32 = SCREEN_WIDTH
	perlinWidth: i32 = SCREEN_HEIGHT

	perlin := rl.GenImagePerlinNoise(
		perlinWidth,
		perlinHeight,
		i32(rand.float32_range(0, 1000)),
		i32(rand.float32_range(0, 1000)),
		0.5,
	)
	defer rl.UnloadImage(perlin)

	return GenerateMapFromImage(Arena, &perlin)
}

GenerateMapFromImageOnDisk :: proc(Arena: ^MemoryArena, FileName: cstring) -> Map {
	mapImage: rl.Image = rl.LoadImage(FileName)
	defer rl.UnloadImage(mapImage)
	return GenerateMapFromImage(Arena, &mapImage)
}


RemoveCircleFromMap :: proc(MapIn: ^Map, Position: rl.Vector2, Radius: f32) {

	positionTileSpace := Position / f32(MapIn.CollisionTileSize)
	scaledRadius := Radius / f32(MapIn.CollisionTileSize)

	columnMin: i32 = i32(
		math.clamp((positionTileSpace.x - scaledRadius), 0.0, f32(len(MapIn.CollisionColumns))),
	)
	columnMax: i32 = i32(
		math.clamp((positionTileSpace.x + scaledRadius), 0.0, f32(len(MapIn.CollisionColumns))),
	)

	localColumnCoord := -scaledRadius

	for i := columnMin; i < columnMax; i += 1 {

		intersectionRef := AxisAlignedLine_Circle_Intersection(
			localColumnCoord,
			Radius / f32(MapIn.CollisionTileSize),
		)

		localColumnCoord += 1
		yMin: int = int(positionTileSpace.y - intersectionRef)
		yMax: int = int(positionTileSpace.y + intersectionRef)

		for j: i32 = 0; j < MapIn.CollisionColumns[i].Count; j += 1 {
			range := &MapIn.CollisionColumns[i].Ranges[j]

			if range.Max > yMax && range.Min < yMin {
				//split
				newRange := &MapIn.CollisionColumns[i].Ranges[MapIn.CollisionColumns[i].Count]
				newRange.Max = range.Max
				newRange.Min = yMax
				range.Max = yMin
				MapIn.CollisionColumns[i].Count += 1
			} else if range.Max <= yMax && range.Min >= yMin {
				range.Max = 0
				range.Min = 0
			} else if range.Max <= yMax && range.Max >= yMin && range.Min <= yMin {
				range.Max = yMin
			} else if range.Max >= yMax && range.Min <= yMax && range.Min >= yMin {
				range.Min = yMax
			}

		}

		rl.BeginTextureMode(MapIn.MaskRenderTexture)
		rl.DrawCircle(
			i32(Position.y),
			MapIn.MaskRenderTexture.texture.height - i32(Position.x),
			Radius,
			rl.WHITE,
		)
		rl.EndTextureMode()
	}
}

AxisAlignedLine_Circle_Intersection :: #force_inline proc(X: f32, Radius: f32) -> f32 {
	return math.sqrt((Radius * Radius) - (X * X))
}


TickPhysicsDynamicCircle :: proc(Body: ^DynamicBody, MapIn: ^Map) {
	collisionSpaceRadius := DYNAMIC_CIRCLE_RADIUS / MapIn.CollisionTileSize
	collisionSpacePosition := Body.Position / f32(MapIn.CollisionTileSize)
	columnMin := int(collisionSpacePosition.x) - collisionSpaceRadius
	columnMin = math.clamp(columnMin, 0, (len(MapIn.CollisionColumns) - 1))
	columnMax := int(math.ceil(collisionSpacePosition.x)) + collisionSpaceRadius
	columnMax = math.clamp(columnMax, 0, (len(MapIn.CollisionColumns) - 1))


	bestCollision: CollisionInfo
	fullCollisionYMin: f32

	for colIndex := columnMin; colIndex <= columnMax; colIndex += 1 {
		column := &MapIn.CollisionColumns[colIndex]
		for sectionIndex: i32 = 0; sectionIndex < column.Count; sectionIndex += 1 {
			section := column.Ranges[sectionIndex]
			collisionRect: Rect = {}
			collisionRect.Min.x = f32(colIndex * MapIn.CollisionTileSize)
			collisionRect.Max.x = collisionRect.Min.x + f32(MapIn.CollisionTileSize)
			collisionRect.Min.y = f32((section.Min) * MapIn.CollisionTileSize)
			collisionRect.Max.y = f32(section.Max * MapIn.CollisionTileSize)
			hit, info := CircleRectCollision(Body.Position, DYNAMIC_CIRCLE_RADIUS, collisionRect)
			if hit {
				if info.PenetrationDistance > bestCollision.PenetrationDistance {
					bestCollision = info
					fullCollisionYMin = collisionRect.Min.y
				}
			}
		}
	}

	if bestCollision.PenetrationDistance > 0 {
		dir: Vector2
		if bestCollision.PenetrationDistance < DYNAMIC_CIRCLE_RADIUS {
			dirNormalized := linalg.vector_normalize(Body.Position - bestCollision.Point)
			dir = dirNormalized * bestCollision.PenetrationDistance
		} else {
			dir = {0, -(Body.Position.y - fullCollisionYMin + DYNAMIC_CIRCLE_RADIUS)}
			Body.Velocity = {}
		}


		Body.Position += dir
		Body.Velocity = Project(Body.Velocity, linalg.vector_normalize(dir))

	}
}

CycleMeasureBegin :: proc() -> u64 {
	return time.read_cycle_counter()
}
CycleMeasureEnd :: proc(TimeStart: u64) -> u64 {
	return time.read_cycle_counter() - TimeStart
}

GetElapsedMiliSeconds :: proc(Start: win32.LARGE_INTEGER, End: win32.LARGE_INTEGER) -> f32 {
	return (cast(f32)(End - Start)) / (cast(f32)PerfCountFrequency * 0.001)
}

GetWallClock :: proc() -> win32.LARGE_INTEGER {
	counter: win32.LARGE_INTEGER
	win32.QueryPerformanceCounter(&counter)
	return counter
}

DrawProfilingData :: proc(Data: ^ProfilingData, Y: i32) {
	height: i32 = 128
	width: i32 = MAX_PROFILING_SAMPLES + 1

	pixelPerMs: f32 = f32(height) / 16.0

	x: i32 = 10
	rl.DrawLine(x, Y, x, Y + height, rl.WHITE)
	rl.DrawLine(x, Y + height, x + width, Y + height, rl.WHITE)


	points: [MAX_PROFILING_SAMPLES]Vector2
	for i: i32 = 0; i < MAX_PROFILING_SAMPLES; i += 1 {
		ms := Data.BallPhysics.Milliseconds[i]
		curX: i32 = x + 1 + i
		if ms <= 0 {
			points[i] = {f32(curX), f32(Y + height)}
			continue
		}

		curY: i32 = Y + height - i32(ms * pixelPerMs)
		if i == Data.CurrentRecordingSample {
			rl.DrawLine(curX, Y + height, curX, curY, rl.ColorLerp(rl.GREEN, rl.RED, ms / 8.0))
		}
		points[i] = {f32(curX), f32(curY)}

	}
	rl.DrawLineStrip(&points[0], MAX_PROFILING_SAMPLES, rl.GREEN)

	eightMsY := Y + height - i32(8 * pixelPerMs)
	rl.DrawLine(x, eightMsY, x + width, eightMsY, rl.DARKPURPLE)
	rl.DrawText("8ms", width + 20, eightMsY - 5, 12, rl.WHITE)
}
