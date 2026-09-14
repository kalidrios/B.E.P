--[[
	© DestructionSimulator [2025]
	TutorialLayouts — Multi-resolution layout coordinate definitions for Tutorial masks, pointers, and headers.
]]--

export type LayoutElement = {
	Position: UDim2,
	Size: UDim2,
	AnchorPoint: Vector2,
	Rotation: number?,
}

export type LayoutPreset = {
	Header: LayoutElement,
	HeaderHeader: LayoutElement,
	SH1: LayoutElement,
	SH2: LayoutElement,
	SH3: LayoutElement,
	SH4: LayoutElement,
	Pointer: LayoutElement,
	ScreenHighlight: LayoutElement,
}

local TutorialLayouts: { [string]: { [string]: LayoutPreset } } = {
	EQUIP_LAUNCHER = {
		FULL_HD = {
			Header = { Position = UDim2.new(0.5, 0, 0.2, 0), Size = UDim2.new(0.4, 0, 0.07, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			HeaderHeader = { Position = UDim2.new(0.5, 0, 1.099, 0), Size = UDim2.new(0.8, 0, 0.45, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			SH1 = { Position = UDim2.new(0.000523, 0, 0.002778, 0), Size = UDim2.new(1, 0, 0.873406, 0), AnchorPoint = Vector2.new(0, 0) },
			SH2 = { Position = UDim2.new(0.432023, 0, 1, 0), Size = UDim2.new(0.070673, 0, 0.007442, 0), AnchorPoint = Vector2.new(0, 0) },
			SH3 = { Position = UDim2.new(0.502696, 0, 0.877809, 0), Size = UDim2.new(0.497304, 0, 0.122191, 0), AnchorPoint = Vector2.new(0, 0) },
			SH4 = { Position = UDim2.new(0, 0, 0.876184, 0), Size = UDim2.new(0.432023, 0, 0.123816, 0), AnchorPoint = Vector2.new(0, 0) },
			Pointer = { Position = UDim2.new(0.507472, 0, 0.872718, 0), Size = UDim2.new(0.076641, 0, 0.089167, 0), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = -90 },
			ScreenHighlight = { Position = UDim2.new(0.429913, 0, 0.877809, 0), Size = UDim2.new(0.072783, 0, 0.121751, 0), AnchorPoint = Vector2.new(0, 0) },
		},
		STANDARD_OR_IPHONE_CLASSIC = {
			Header = { Position = UDim2.new(0.5, 0, 0.222253, 0), Size = UDim2.new(0.4, 0, 0.07, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			HeaderHeader = { Position = UDim2.new(0.5, 0, 1.099, 0), Size = UDim2.new(0.8, 0, 0.45, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			SH1 = { Position = UDim2.new(0.000523, 0, 0.002778, 0), Size = UDim2.new(1, 0, 0.835093, 0), AnchorPoint = Vector2.new(0, 0) },
			SH2 = { Position = UDim2.new(0.415843, 0, 0.992516, 0), Size = UDim2.new(0.086853, 0, 0.014927, 0), AnchorPoint = Vector2.new(0, 0) },
			SH3 = { Position = UDim2.new(0.503477, 0, 0.837871, 0), Size = UDim2.new(0.496523, 0, 0.162129, 0), AnchorPoint = Vector2.new(0, 0) },
			SH4 = { Position = UDim2.new(0, 0, 0.837871, 0), Size = UDim2.new(0.415843, 0, 0.162130, 0), AnchorPoint = Vector2.new(0, 0) },
			Pointer = { Position = UDim2.new(0.500440, 0, 0.830993, 0), Size = UDim2.new(0.076641, 0, 0.089167, 0), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = -90 },
			ScreenHighlight = { Position = UDim2.new(0.412524, 0, 0.837871, 0), Size = UDim2.new(0.093297, 0, 0.154645, 0), AnchorPoint = Vector2.new(0, 0) },
		},
		MOBILE_WIDESCREEN = {
			Header = { Position = UDim2.new(0.5, 0, 0.222253, 0), Size = UDim2.new(0.4, 0, 0.07, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			HeaderHeader = { Position = UDim2.new(0.5, 0, 1.099, 0), Size = UDim2.new(0.8, 0, 0.45, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			SH1 = { Position = UDim2.new(0.000523, 0, 0.002778, 0), Size = UDim2.new(1, 0, 0.769971, 0), AnchorPoint = Vector2.new(0, 0) },
			SH2 = { Position = UDim2.new(0.425242, 0, 0.927140, 0), Size = UDim2.new(0.072649, 0, 0.080303, 0), AnchorPoint = Vector2.new(0, 0) },
			SH3 = { Position = UDim2.new(0.497891, 0, 0.772749, 0), Size = UDim2.new(0.502109, 0, 0.227251, 0), AnchorPoint = Vector2.new(0, 0) },
			SH4 = { Position = UDim2.new(0, 0, 0.772749, 0), Size = UDim2.new(0.425242, 0, 0.227251, 0), AnchorPoint = Vector2.new(0, 0) },
			Pointer = { Position = UDim2.new(0.491502, 0, 0.780146, 0), Size = UDim2.new(0.076641, 0, 0.089167, 0), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = -90 },
			ScreenHighlight = { Position = UDim2.new(0.425000, 0, 0.772495, 0), Size = UDim2.new(0.072649, 0, 0.154645, 0), AnchorPoint = Vector2.new(0, 0) },
		},
		TABLET = {
			Header = { Position = UDim2.new(0.5, 0, 0.222253, 0), Size = UDim2.new(0.4, 0, 0.07, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			HeaderHeader = { Position = UDim2.new(0.5, 0, 1.099, 0), Size = UDim2.new(0.8, 0, 0.45, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			SH1 = { Position = UDim2.new(-0.000259, 0, -0.000982, 0), Size = UDim2.new(1, 0, 0.855786, 0), AnchorPoint = Vector2.new(0, 0) },
			SH2 = { Position = UDim2.new(0.412504, 0, 0.992071, 0), Size = UDim2.new(0.085386, 0, 0.015372, 0), AnchorPoint = Vector2.new(0, 0) },
			SH3 = { Position = UDim2.new(0.497891, 0, 0.854805, 0), Size = UDim2.new(0.502109, 0, 0.145195, 0), AnchorPoint = Vector2.new(0, 0) },
			SH4 = { Position = UDim2.new(0, 0, 0.854805, 0), Size = UDim2.new(0.412504, 0, 0.145196, 0), AnchorPoint = Vector2.new(0, 0) },
			Pointer = { Position = UDim2.new(0.496975, 0, 0.860346, 0), Size = UDim2.new(0.076641, 0, 0.089167, 0), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = -90 },
			ScreenHighlight = { Position = UDim2.new(0.412504, 0, 0.854805, 0), Size = UDim2.new(0.087335, 0, 0.137153, 0), AnchorPoint = Vector2.new(0, 0) },
		},
	},

	SELL_BLOCKS = {
		UNIVERSAL = {
			Header = { Position = UDim2.new(0.5, 0, 0.222253, 0), Size = UDim2.new(0.4, 0, 0.07, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			HeaderHeader = { Position = UDim2.new(0.5, 0, 1.099, 0), Size = UDim2.new(0.8, 0, 0.45, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			SH1 = { Position = UDim2.new(-0.000259, 0, -0.000054, 0), Size = UDim2.new(1, 0, 0.607174, 0), AnchorPoint = Vector2.new(0, 0) },
			SH2 = { Position = UDim2.new(0.300000, 0, 0.795798, 0), Size = UDim2.new(0.166130, 0, 0.211645, 0), AnchorPoint = Vector2.new(0, 0) },
			SH3 = { Position = UDim2.new(0.466130, 0, 0.607729, 0), Size = UDim2.new(0.533870, 0, 0.392271, 0), AnchorPoint = Vector2.new(0, 0) },
			SH4 = { Position = UDim2.new(0, 0, 0.607729, 0), Size = UDim2.new(0.300000, 0, 0.392271, 0), AnchorPoint = Vector2.new(0, 0) },
			Pointer = { Position = UDim2.new(0.454787, 0, 0.646061, 0), Size = UDim2.new(0.076641, 0, 0.089167, 0), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = -90 },
			ScreenHighlight = { Position = UDim2.new(0.344385, 0, 0.951187, 0), Size = UDim2.new(0.004137, 0, -0.005845, 0), AnchorPoint = Vector2.new(0, 0) },
		},
		MOBILE_WIDESCREEN = {
			Header = { Position = UDim2.new(0.495531, 0, 0.110873, 0), Size = UDim2.new(0.4, 0, 0.07, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			HeaderHeader = { Position = UDim2.new(0.5, 0, 1.099, 0), Size = UDim2.new(0.8, 0, 0.45, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			SH1 = { Position = UDim2.new(-0.000259, 0, -0.000054, 0), Size = UDim2.new(1, 0, 0.588057, 0), AnchorPoint = Vector2.new(0, 0) },
			SH2 = { Position = UDim2.new(0.340000, 0, 0.749764, 0), Size = UDim2.new(0.133384, 0, 0.257680, 0), AnchorPoint = Vector2.new(0, 0) },
			SH3 = { Position = UDim2.new(0.475360, 0, 0.588004, 0), Size = UDim2.new(0.524640, 0, 0.411996, 0), AnchorPoint = Vector2.new(0, 0) },
			SH4 = { Position = UDim2.new(0, 0, 0.588004, 0), Size = UDim2.new(0.340000, 0, 0.411997, 0), AnchorPoint = Vector2.new(0, 0) },
			Pointer = { Position = UDim2.new(0.461491, 0, 0.617005, 0), Size = UDim2.new(0.076641, 0, 0.089167, 0), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = -90 },
			ScreenHighlight = { Position = UDim2.new(0.344385, 0, 0.951187, 0), Size = UDim2.new(0.004137, 0, -0.005845, 0), AnchorPoint = Vector2.new(0, 0) },
		},
	},

	SHOP_BACKPACK = {
		STANDARD_OR_IPHONE_CLASSIC = {
			Header = { Position = UDim2.new(0.495531, 0, 0.110873, 0), Size = UDim2.new(0.4, 0, 0.07, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			HeaderHeader = { Position = UDim2.new(0.5, 0, 1.099, 0), Size = UDim2.new(0.8, 0, 0.45, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			SH1 = { Position = UDim2.new(-0.000259, 0, -0.000054, 0), Size = UDim2.new(1, 0, 0.592731, 0), AnchorPoint = Vector2.new(0, 0) },
			SH2 = { Position = UDim2.new(0.146504, 0, 0.704544, 0), Size = UDim2.new(0.059641, 0, 0.302900, 0), AnchorPoint = Vector2.new(0, 0) },
			SH3 = { Position = UDim2.new(0.205624, 0, 0.592642, 0), Size = UDim2.new(0.793855, 0, 0.419418, 0), AnchorPoint = Vector2.new(0, 0) },
			SH4 = { Position = UDim2.new(-0.010417, 0, 0.592642, 0), Size = UDim2.new(0.156921, 0, 0.407358, 0), AnchorPoint = Vector2.new(0, 0) },
			Pointer = { Position = UDim2.new(0.206283, 0, 0.619788, 0), Size = UDim2.new(0.076641, 0, 0.089167, 0), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = -90 },
			ScreenHighlight = { Position = UDim2.new(0.146504, 0, 0.704544, 0), Size = UDim2.new(0.059641, 0, -0.110047, 0), AnchorPoint = Vector2.new(0, 0) },
		},
		MOBILE_WIDESCREEN = {
			Header = { Position = UDim2.new(0.499089, 0, 0.049176, 0), Size = UDim2.new(0.4, 0, 0.07, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			HeaderHeader = { Position = UDim2.new(0.5, 0, 1.099, 0), Size = UDim2.new(0.8, 0, 0.45, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			SH1 = { Position = UDim2.new(-0.000259, 0, -0.000054, 0), Size = UDim2.new(1, 0, 0.571552, 0), AnchorPoint = Vector2.new(0, 0) },
			SH2 = { Position = UDim2.new(0.197024, 0, 0.681408, 0), Size = UDim2.new(0.048060, 0, 0.318324, 0), AnchorPoint = Vector2.new(0, 0) },
			SH3 = { Position = UDim2.new(0.245084, 0, 0.569506, 0), Size = UDim2.new(0.769817, 0, 0.430495, 0), AnchorPoint = Vector2.new(0, 0) },
			SH4 = { Position = UDim2.new(-0.010417, 0, 0.571498, 0), Size = UDim2.new(0.207440, 0, 0.428503, 0), AnchorPoint = Vector2.new(0, 0) },
			Pointer = { Position = UDim2.new(0.243056, 0, 0.570945, 0), Size = UDim2.new(0.076641, 0, 0.089167, 0), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = -90 },
			ScreenHighlight = { Position = UDim2.new(0.197024, 0, 0.681408, 0), Size = UDim2.new(0.048060, 0, -0.109910, 0), AnchorPoint = Vector2.new(0, 0) },
		},
		TABLET = {
			Header = { Position = UDim2.new(0.499871, 0, 0.150680, 0), Size = UDim2.new(0.4, 0, 0.07, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			HeaderHeader = { Position = UDim2.new(0.5, 0, 1.099, 0), Size = UDim2.new(0.8, 0, 0.45, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			SH1 = { Position = UDim2.new(-0.000259, 0, -0.000054, 0), Size = UDim2.new(1, 0, 0.590446, 0), AnchorPoint = Vector2.new(0, 0) },
			SH2 = { Position = UDim2.new(0.149344, 0, 0.681408, 0), Size = UDim2.new(0.050342, 0, 0.318324, 0), AnchorPoint = Vector2.new(0, 0) },
			SH3 = { Position = UDim2.new(0.199686, 0, 0.590393, 0), Size = UDim2.new(0.815214, 0, 0.409608, 0), AnchorPoint = Vector2.new(0, 0) },
			SH4 = { Position = UDim2.new(-0.010417, 0, 0.590393, 0), Size = UDim2.new(0.159761, 0, 0.409608, 0), AnchorPoint = Vector2.new(0, 0) },
			Pointer = { Position = UDim2.new(0.212564, 0, 0.578463, 0), Size = UDim2.new(0.076641, 0, 0.089167, 0), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = -90 },
			ScreenHighlight = { Position = UDim2.new(0.149454, 0, 0.664979, 0), Size = UDim2.new(0.050342, 0, -0.076618, 0), AnchorPoint = Vector2.new(0, 0) },
		},
	},

	SHOP_RIGHT = {
		STANDARD_OR_IPHONE_CLASSIC = {
			Header = { Position = UDim2.new(0.519142, 0, 0.100587, 0), Size = UDim2.new(0.4, 0, 0.07, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			HeaderHeader = { Position = UDim2.new(0.5, 0, 1.099, 0), Size = UDim2.new(0.8, 0, 0.45, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			SH1 = { Position = UDim2.new(-0.000000, 0, -0.013092, 0), Size = UDim2.new(1.007062, 0, 0.480280, 0), AnchorPoint = Vector2.new(0, 0) },
			SH2 = { Position = UDim2.new(0.776477, 0, 0.579000, 0), Size = UDim2.new(0.060818, 0, 0.421000, 0), AnchorPoint = Vector2.new(0, 0) },
			SH3 = { Position = UDim2.new(0.837295, 0, 0.467188, 0), Size = UDim2.new(0.177605, 0, 0.532812, 0), AnchorPoint = Vector2.new(0, 0) },
			SH4 = { Position = UDim2.new(-0.010417, 0, 0.467188, 0), Size = UDim2.new(0.786894, 0, 0.532812, 0), AnchorPoint = Vector2.new(0, 0) },
			Pointer = { Position = UDim2.new(0.848208, 0, 0.473119, 0), Size = UDim2.new(0.076641, 0, 0.089167, 0), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = -90 },
			ScreenHighlight = { Position = UDim2.new(0.776477, 0, 0.579000, 0), Size = UDim2.new(0.060535, 0, -0.111632, 0), AnchorPoint = Vector2.new(0, 0) },
		},
		MOBILE_WIDESCREEN = {
			Header = { Position = UDim2.new(0.519142, 0, 0.100587, 0), Size = UDim2.new(0.4, 0, 0.07, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			HeaderHeader = { Position = UDim2.new(0.5, 0, 1.099, 0), Size = UDim2.new(0.8, 0, 0.45, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			SH1 = { Position = UDim2.new(-0.000000, 0, -0.013092, 0), Size = UDim2.new(1.007062, 0, 0.457497, 0), AnchorPoint = Vector2.new(0, 0) },
			SH2 = { Position = UDim2.new(0.747427, 0, 0.575282, 0), Size = UDim2.new(0.060535, 0, 0.424718, 0), AnchorPoint = Vector2.new(0, 0) },
			SH3 = { Position = UDim2.new(0.807961, 0, 0.448923, 0), Size = UDim2.new(0.206939, 0, 0.551078, 0), AnchorPoint = Vector2.new(0, 0) },
			SH4 = { Position = UDim2.new(-0.039467, 0, 0.444405, 0), Size = UDim2.new(0.786894, 0, 0.550752, 0), AnchorPoint = Vector2.new(0, 0) },
			Pointer = { Position = UDim2.new(0.813571, 0, 0.431957, 0), Size = UDim2.new(0.076641, 0, 0.089167, 0), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = -90 },
			ScreenHighlight = { Position = UDim2.new(0.749661, 0, 0.557208, 0), Size = UDim2.new(0.060535, 0, -0.111632, 0), AnchorPoint = Vector2.new(0, 0) },
		},
		TABLET = {
			Header = { Position = UDim2.new(0.523317, 0, 0.100587, 0), Size = UDim2.new(0.4, 0, 0.07, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			HeaderHeader = { Position = UDim2.new(0.5, 0, 1.099, 0), Size = UDim2.new(0.8, 0, 0.45, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			SH1 = { Position = UDim2.new(-0.000000, 0, -0.013092, 0), Size = UDim2.new(1.007062, 0, 0.481225, 0), AnchorPoint = Vector2.new(0, 0) },
			SH2 = { Position = UDim2.new(0.776244, 0, 0.575282, 0), Size = UDim2.new(0.065143, 0, 0.424718, 0), AnchorPoint = Vector2.new(0, 0) },
			SH3 = { Position = UDim2.new(0.841388, 0, 0.468133, 0), Size = UDim2.new(0.173513, 0, 0.530614, 0), AnchorPoint = Vector2.new(0, 0) },
			SH4 = { Position = UDim2.new(-0.039467, 0, 0.468133, 0), Size = UDim2.new(0.815711, 0, 0.527025, 0), AnchorPoint = Vector2.new(0, 0) },
			Pointer = { Position = UDim2.new(0.845672, 0, 0.460564, 0), Size = UDim2.new(0.076641, 0, 0.089167, 0), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = -90 },
			ScreenHighlight = { Position = UDim2.new(0.776245, 0, 0.579765, 0), Size = UDim2.new(0.060535, 0, -0.111632, 0), AnchorPoint = Vector2.new(0, 0) },
		},
	},

	SHOP_BUY = {
		STANDARD_OR_IPHONE_CLASSIC = {
			Header = { Position = UDim2.new(0.523317, 0, 0.100587, 0), Size = UDim2.new(0.4, 0, 0.07, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			HeaderHeader = { Position = UDim2.new(0.5, 0, 1.099, 0), Size = UDim2.new(0.8, 0, 0.45, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			SH1 = { Position = UDim2.new(-0.000000, 0, -0.013092, 0), Size = UDim2.new(1.007062, 0, 0.634261, 0), AnchorPoint = Vector2.new(0, 0) },
			SH2 = { Position = UDim2.new(0.437976, 0, 0.812496, 0), Size = UDim2.new(0.172622, 0, 0.187504, 0), AnchorPoint = Vector2.new(0, 0) },
			SH3 = { Position = UDim2.new(0.610598, 0, 0.621169, 0), Size = UDim2.new(0.401698, 0, 0.378506, 0), AnchorPoint = Vector2.new(0, 0) },
			SH4 = { Position = UDim2.new(-0.039467, 0, 0.621169, 0), Size = UDim2.new(0.477443, 0, 0.377578, 0), AnchorPoint = Vector2.new(0, 0) },
			Pointer = { Position = UDim2.new(0.606610, 0, 0.649804, 0), Size = UDim2.new(0.076641, 0, 0.089167, 0), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = -90 },
			ScreenHighlight = { Position = UDim2.new(0.837214, 0, 0.578837, 0), Size = UDim2.new(0.001649, 0, -0.026836, 0), AnchorPoint = Vector2.new(0, 0) },
		},
		MOBILE_WIDESCREEN = {
			Header = { Position = UDim2.new(0.521083, 0, 0.071532, 0), Size = UDim2.new(0.4, 0, 0.07, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			HeaderHeader = { Position = UDim2.new(0.5, 0, 1.099, 0), Size = UDim2.new(0.8, 0, 0.45, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			SH1 = { Position = UDim2.new(0.002235, 0, -0.046990, 0), Size = UDim2.new(1.007062, 0, 0.634261, 0), AnchorPoint = Vector2.new(0, 0) },
			SH2 = { Position = UDim2.new(0.437976, 0, 0.801913, 0), Size = UDim2.new(0.172622, 0, 0.198087, 0), AnchorPoint = Vector2.new(0, 0) },
			SH3 = { Position = UDim2.new(0.610598, 0, 0.587271, 0), Size = UDim2.new(0.401698, 0, 0.412404, 0), AnchorPoint = Vector2.new(0, 0) },
			SH4 = { Position = UDim2.new(-0.039467, 0, 0.587271, 0), Size = UDim2.new(0.477443, 0, 0.411476, 0), AnchorPoint = Vector2.new(0, 0) },
			Pointer = { Position = UDim2.new(0.589850, 0, 0.618327, 0), Size = UDim2.new(0.076641, 0, 0.089167, 0), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = -90 },
			ScreenHighlight = { Position = UDim2.new(0.837214, 0, 0.578837, 0), Size = UDim2.new(0.001649, 0, -0.026836, 0), AnchorPoint = Vector2.new(0, 0) },
		},
		TABLET = {
			Header = { Position = UDim2.new(0.521083, 0, 0.071532, 0), Size = UDim2.new(0.4, 0, 0.07, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			HeaderHeader = { Position = UDim2.new(0.5, 0, 1.099, 0), Size = UDim2.new(0.8, 0, 0.45, 0), AnchorPoint = Vector2.new(0.5, 0.5) },
			SH1 = { Position = UDim2.new(-0.000008, 0, -0.036965, 0), Size = UDim2.new(1.010868, 0, 0.654568, 0), AnchorPoint = Vector2.new(0, 0) },
			SH2 = { Position = UDim2.new(0.437976, 0, 0.763822, 0), Size = UDim2.new(0.172622, 0, 0.236178, 0), AnchorPoint = Vector2.new(0, 0) },
			SH3 = { Position = UDim2.new(0.610598, 0, 0.617603, 0), Size = UDim2.new(0.401698, 0, 0.382072, 0), AnchorPoint = Vector2.new(0, 0) },
			SH4 = { Position = UDim2.new(-0.039467, 0, 0.617603, 0), Size = UDim2.new(0.477443, 0, 0.381144, 0), AnchorPoint = Vector2.new(0, 0) },
			Pointer = { Position = UDim2.new(0.604314, 0, 0.622394, 0), Size = UDim2.new(0.076641, 0, 0.089167, 0), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = -90 },
			ScreenHighlight = { Position = UDim2.new(0.837214, 0, 0.578837, 0), Size = UDim2.new(0.001649, 0, -0.026836, 0), AnchorPoint = Vector2.new(0, 0) },
		},
	},
}

return TutorialLayouts
