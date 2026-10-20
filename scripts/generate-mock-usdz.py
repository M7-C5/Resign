#!/usr/bin/env python3
"""
generate-mock-usdz.py
Resign — Spatial Room Layout & Light Simulation Mock USDZ Generator

Generates a fully compliant, physically scaled standard furnished room:
- Room: 5.0m (W) x 4.2m (D) x 2.6m (H)
- 1 Bed (1.6m x 2.0m Queen with headboard, pillows, duvet)
- 1 Desk / Workstation (1.2m x 0.65m x 0.75m Oak & Black Metal)
- 1 Chair (Ergonomic Office Chair with Charcoal Fabric)
- 1 Sofa (2.0m 3-seater in Slate Blue Fabric with cushions)
- 1 Closet / Cupboard (1.2m x 0.6m x 2.1m Modern Wardrobe with Brass Handles)
- 1 TV & Media Console (55-inch OLED TV with Walnut Stand)
- 1 Window (1.6m x 1.2m East-facing window with frame, mullion, and architectural glass)
- 1 Door (0.9m x 2.1m South-facing entry door with frame and steel lever handle)

Outputs:
- Resign/Resources/MockRoom.usda (ASCII Universal Scene Description)
- Resign/Resources/MockRoom.usdz (Zipped USD package verified with usdchecker)
"""

import os
import sys
import subprocess

def create_pbr_material(name, diffuse, roughness=0.5, metallic=0.0, opacity=1.0, ior=1.5):
    diff_r, diff_g, diff_b = diffuse
    opacity_str = f"float inputs:opacity = {opacity:.2f}\n                " if opacity < 1.0 else ""
    ior_str = f"float inputs:ior = {ior:.2f}\n                " if opacity < 1.0 else ""
    return f"""        def Material "{name}"
        {{
            def Shader "PBRShader"
            {{
                uniform token info:id = "UsdPreviewSurface"
                color3f inputs:diffuseColor = ({diff_r:.3f}, {diff_g:.3f}, {diff_b:.3f})
                float inputs:roughness = {roughness:.2f}
                float inputs:metallic = {metallic:.2f}
                {opacity_str}{ior_str}token outputs:surface
            }}
            token outputs:surface.connect = </Room/Materials/{name}/PBRShader.outputs:surface>
        }}
"""

def create_box_mesh(name, x0, y0, z0, x1, y1, z1, mat_path, category=None, invisible=False):
    # Ensure min < max
    xmin, xmax = min(x0, x1), max(x0, x1)
    ymin, ymax = min(y0, y1), max(y0, y1)
    zmin, zmax = min(z0, z1), max(z0, z1)

    # 24 distinct vertices (4 per face) for razor-sharp flat architectural shading
    points = [
        # 0-3: Front (+Z, normal = 0, 0, 1)
        (xmin, ymin, zmax), (xmax, ymin, zmax), (xmax, ymax, zmax), (xmin, ymax, zmax),
        # 4-7: Back (-Z, normal = 0, 0, -1)
        (xmax, ymin, zmin), (xmin, ymin, zmin), (xmin, ymax, zmin), (xmax, ymax, zmin),
        # 8-11: Left (-X, normal = -1, 0, 0)
        (xmin, ymin, zmin), (xmin, ymin, zmax), (xmin, ymax, zmax), (xmin, ymax, zmin),
        # 12-15: Right (+X, normal = 1, 0, 0)
        (xmax, ymin, zmax), (xmax, ymin, zmin), (xmax, ymax, zmin), (xmax, ymax, zmax),
        # 16-19: Top (+Y, normal = 0, 1, 0)
        (xmin, ymax, zmax), (xmax, ymax, zmax), (xmax, ymax, zmin), (xmin, ymax, zmin),
        # 20-23: Bottom (-Y, normal = 0, -1, 0)
        (xmin, ymin, zmin), (xmax, ymin, zmin), (xmax, ymin, zmax), (xmin, ymin, zmax)
    ]
    indices = list(range(24))
    normals = [
        (0, 0, 1), (0, 0, 1), (0, 0, 1), (0, 0, 1),
        (0, 0, -1), (0, 0, -1), (0, 0, -1), (0, 0, -1),
        (-1, 0, 0), (-1, 0, 0), (-1, 0, 0), (-1, 0, 0),
        (1, 0, 0), (1, 0, 0), (1, 0, 0), (1, 0, 0),
        (0, 1, 0), (0, 1, 0), (0, 1, 0), (0, 1, 0),
        (0, -1, 0), (0, -1, 0), (0, -1, 0), (0, -1, 0)
    ]
    uvs = [(0, 0), (1, 0), (1, 1), (0, 1)] * 6

    pts_str = ", ".join(f"({p[0]:.3f}, {p[1]:.3f}, {p[2]:.3f})" for p in points)
    idx_str = ", ".join(str(i) for i in indices)
    norm_str = ", ".join(f"({n[0]}, {n[1]}, {n[2]})" for n in normals)
    uv_str = ", ".join(f"({u[0]}, {u[1]})" for u in uvs)

    cat_meta = f'\n        custom string resign:category = "{category}"' if category else ""
    vis_meta = '\n        uniform token visibility = "invisible"' if invisible else ""

    return f"""    def Mesh "{name}" (
        prepend apiSchemas = ["MaterialBindingAPI"]
    )
    {{
        uniform token subdivisionScheme = "none"{vis_meta}
        rel material:binding = <{mat_path}>{cat_meta}
        float3[] extent = [({xmin:.3f}, {ymin:.3f}, {zmin:.3f}), ({xmax:.3f}, {ymax:.3f}, {zmax:.3f})]
        int[] faceVertexCounts = [4, 4, 4, 4, 4, 4]
        int[] faceVertexIndices = [{idx_str}]
        normal3f[] normals = [{norm_str}] (
            interpolation = "vertex"
        )
        texCoord2f[] primvars:st = [{uv_str}] (
            interpolation = "vertex"
        )
        point3f[] points = [{pts_str}]
    }}
"""

def generate_scene():
    materials = [
        create_pbr_material("Mat_Floor", (0.76, 0.61, 0.41), roughness=0.35, metallic=0.0),
        create_pbr_material("Mat_Ceiling", (0.95, 0.95, 0.96), roughness=0.90, metallic=0.0),
        create_pbr_material("Mat_Wall", (0.91, 0.90, 0.88), roughness=0.85, metallic=0.0),
        create_pbr_material("Mat_WoodOak", (0.82, 0.68, 0.49), roughness=0.40, metallic=0.0),
        create_pbr_material("Mat_WoodWalnut", (0.28, 0.20, 0.14), roughness=0.45, metallic=0.0),
        create_pbr_material("Mat_WoodAsh", (0.64, 0.49, 0.35), roughness=0.45, metallic=0.0),
        create_pbr_material("Mat_MetalBlack", (0.12, 0.12, 0.12), roughness=0.30, metallic=0.8),
        create_pbr_material("Mat_MetalChrome", (0.80, 0.82, 0.84), roughness=0.15, metallic=0.95),
        create_pbr_material("Mat_MetalBrass", (0.78, 0.64, 0.35), roughness=0.25, metallic=0.85),
        create_pbr_material("Mat_FabricBed", (0.93, 0.93, 0.92), roughness=0.75, metallic=0.0),
        create_pbr_material("Mat_BedHeadboard", (0.35, 0.37, 0.40), roughness=0.70, metallic=0.0),
        create_pbr_material("Mat_BedRunner", (0.17, 0.24, 0.31), roughness=0.80, metallic=0.0),
        create_pbr_material("Mat_SofaFabric", (0.23, 0.30, 0.38), roughness=0.70, metallic=0.0),
        create_pbr_material("Mat_SofaCushion", (0.86, 0.83, 0.77), roughness=0.80, metallic=0.0),
        create_pbr_material("Mat_ChairFabric", (0.20, 0.22, 0.24), roughness=0.65, metallic=0.0),
        create_pbr_material("Mat_ClosetBody", (0.92, 0.93, 0.94), roughness=0.50, metallic=0.0),
        create_pbr_material("Mat_TVScreen", (0.04, 0.04, 0.05), roughness=0.04, metallic=0.1),
        create_pbr_material("Mat_Glass", (0.85, 0.92, 0.98), roughness=0.02, metallic=0.05, opacity=0.15, ior=1.52),
    ]

    mat_block = "".join(materials)

    # Room Dimensions
    # Width X: [-2.50, +2.50] (5.0m)
    # Depth Z: [-2.10, +2.10] (4.2m)
    # Height Y: [0.00, 2.60] (2.6m)
    # Wall thickness: 0.10m
    W_half = 2.50
    D_half = 2.10
    H = 2.60
    T = 0.10

    # East Window Opening:
    w_z0, w_z1 = -0.80, 0.80
    w_y0, w_y1 = 0.85, 2.05

    # South Door Opening:
    d_x0, d_x1 = -1.95, -1.05
    d_y0, d_y1 = 0.00, 2.10

    structure_meshes = [
        # Floor (y: -0.05 to 0.00)
        create_box_mesh("Floor", -W_half, -0.05, -D_half, W_half, 0.00, D_half, "/Room/Materials/Mat_Floor", "floor"),
        # Ceiling (Invisible by default for dollhouse 3D view; geometry available for raycast occlusion)
        create_box_mesh("Ceiling", -W_half, H, -D_half, W_half, H + 0.05, D_half, "/Room/Materials/Mat_Ceiling", "ceiling", invisible=True),
        # North Wall (Solid)
        create_box_mesh("Wall_North", -W_half, 0.00, -D_half - T, W_half, H, -D_half, "/Room/Materials/Mat_Wall", "wall"),
        # West Wall (Solid)
        create_box_mesh("Wall_West", -W_half - T, 0.00, -D_half, -W_half, H, D_half, "/Room/Materials/Mat_Wall", "wall"),

        # South Wall Segments (Around Door)
        create_box_mesh("Wall_South_Left", -W_half, 0.00, D_half, d_x0, H, D_half + T, "/Room/Materials/Mat_Wall", "wall"),
        create_box_mesh("Wall_South_Right", d_x1, 0.00, D_half, W_half, H, D_half + T, "/Room/Materials/Mat_Wall", "wall"),
        create_box_mesh("Wall_South_Lintel", d_x0, d_y1, D_half, d_x1, H, D_half + T, "/Room/Materials/Mat_Wall", "wall"),

        # East Wall Segments (Around Window)
        create_box_mesh("Wall_East_North", W_half, 0.00, -D_half, W_half + T, H, w_z0, "/Room/Materials/Mat_Wall", "wall"),
        create_box_mesh("Wall_East_South", W_half, 0.00, w_z1, W_half + T, H, D_half, "/Room/Materials/Mat_Wall", "wall"),
        create_box_mesh("Wall_East_Bottom", W_half, 0.00, w_z0, W_half + T, w_y0, w_z1, "/Room/Materials/Mat_Wall", "wall"),
        create_box_mesh("Wall_East_Top", W_half, w_y1, w_z0, W_half + T, H, w_z1, "/Room/Materials/Mat_Wall", "wall"),
    ]

    # Openings: Window & Door
    window_meshes = [
        # Outer Frame (Dark Charcoal Aluminum)
        create_box_mesh("Frame_Bottom", W_half - 0.02, w_y0 - 0.03, w_z0 - 0.03, W_half + T + 0.02, w_y0 + 0.03, w_z1 + 0.03, "/Room/Materials/Mat_MetalBlack"),
        create_box_mesh("Frame_Top", W_half - 0.02, w_y1 - 0.03, w_z0 - 0.03, W_half + T + 0.02, w_y1 + 0.03, w_z1 + 0.03, "/Room/Materials/Mat_MetalBlack"),
        create_box_mesh("Frame_Left", W_half - 0.02, w_y0, w_z0 - 0.03, W_half + T + 0.02, w_y1, w_z0 + 0.03, "/Room/Materials/Mat_MetalBlack"),
        create_box_mesh("Frame_Right", W_half - 0.02, w_y0, w_z1 - 0.03, W_half + T + 0.02, w_y1, w_z1 + 0.03, "/Room/Materials/Mat_MetalBlack"),
        # Center Mullion
        create_box_mesh("Frame_Mullion", W_half - 0.01, w_y0, -0.025, W_half + T + 0.01, w_y1, 0.025, "/Room/Materials/Mat_MetalBlack"),
        # Architectural Glass (Translucent)
        create_box_mesh("Glass", W_half + 0.04, w_y0 + 0.02, w_z0 + 0.02, W_half + 0.06, w_y1 - 0.02, w_z1 - 0.02, "/Room/Materials/Mat_Glass", "window_glass"),
    ]

    door_meshes = [
        # Frame Casing
        create_box_mesh("Frame_Left", d_x0 - 0.03, 0.00, D_half - 0.01, d_x0 + 0.02, d_y1 + 0.03, D_half + T + 0.01, "/Room/Materials/Mat_WoodAsh"),
        create_box_mesh("Frame_Right", d_x1 - 0.02, 0.00, D_half - 0.01, d_x1 + 0.03, d_y1 + 0.03, D_half + T + 0.01, "/Room/Materials/Mat_WoodAsh"),
        create_box_mesh("Frame_Top", d_x0 - 0.03, d_y1, D_half - 0.01, d_x1 + 0.03, d_y1 + 0.04, D_half + T + 0.01, "/Room/Materials/Mat_WoodAsh"),
        # Door Slab (Flush in frame)
        create_box_mesh("Panel", d_x0 + 0.01, 0.00, D_half + 0.03, d_x1 - 0.01, d_y1, D_half + 0.07, "/Room/Materials/Mat_WoodAsh", "door"),
        # Handle Lever
        create_box_mesh("Handle", d_x1 - 0.12, 0.98, D_half + 0.01, d_x1 - 0.04, 1.02, D_half + 0.09, "/Room/Materials/Mat_MetalChrome"),
    ]

    # Furniture 1: Bed
    bed_meshes = [
        # Base platform
        create_box_mesh("Base", -2.10, 0.00, -2.00, -0.50, 0.30, 0.00, "/Room/Materials/Mat_WoodWalnut"),
        # Mattress
        create_box_mesh("Mattress", -2.05, 0.30, -1.95, -0.55, 0.58, -0.05, "/Room/Materials/Mat_FabricBed", "bed"),
        # Headboard
        create_box_mesh("Headboard", -2.12, 0.00, -2.08, -0.48, 1.05, -1.98, "/Room/Materials/Mat_BedHeadboard"),
        # Pillows (Left & Right)
        create_box_mesh("Pillow_Left", -1.98, 0.58, -1.88, -1.35, 0.70, -1.45, "/Room/Materials/Mat_FabricBed"),
        create_box_mesh("Pillow_Right", -1.25, 0.58, -1.88, -0.62, 0.70, -1.45, "/Room/Materials/Mat_FabricBed"),
        # Duvet Runner
        create_box_mesh("DuvetRunner", -2.06, 0.585, -0.60, -0.54, 0.60, -0.04, "/Room/Materials/Mat_BedRunner"),
    ]

    # Furniture 2: Desk / Table
    desk_meshes = [
        # Tabletop
        create_box_mesh("Top", 1.80, 0.71, -1.80, 2.45, 0.75, -0.60, "/Room/Materials/Mat_WoodOak", "desk"),
        # 4 Metal Legs
        create_box_mesh("Leg_NW", 1.82, 0.00, -1.78, 1.86, 0.71, -1.74, "/Room/Materials/Mat_MetalBlack"),
        create_box_mesh("Leg_NE", 2.39, 0.00, -1.78, 2.43, 0.71, -1.74, "/Room/Materials/Mat_MetalBlack"),
        create_box_mesh("Leg_SW", 1.82, 0.00, -0.66, 1.86, 0.71, -0.62, "/Room/Materials/Mat_MetalBlack"),
        create_box_mesh("Leg_SE", 2.39, 0.00, -0.66, 2.43, 0.71, -0.62, "/Room/Materials/Mat_MetalBlack"),
    ]

    # Furniture 3: Chair
    chair_meshes = [
        # Seat
        create_box_mesh("Seat", 1.20, 0.42, -1.42, 1.64, 0.48, -0.98, "/Room/Materials/Mat_ChairFabric", "chair"),
        # Backrest (on west side of seat)
        create_box_mesh("Backrest", 1.18, 0.48, -1.42, 1.24, 0.88, -0.98, "/Room/Materials/Mat_ChairFabric"),
        # 4 Legs
        create_box_mesh("Leg_NW", 1.22, 0.00, -1.40, 1.26, 0.42, -1.36, "/Room/Materials/Mat_MetalBlack"),
        create_box_mesh("Leg_NE", 1.58, 0.00, -1.40, 1.62, 0.42, -1.36, "/Room/Materials/Mat_MetalBlack"),
        create_box_mesh("Leg_SW", 1.22, 0.00, -1.04, 1.26, 0.42, -1.00, "/Room/Materials/Mat_MetalBlack"),
        create_box_mesh("Leg_SE", 1.58, 0.00, -1.04, 1.62, 0.42, -1.00, "/Room/Materials/Mat_MetalBlack"),
    ]

    # Furniture 4: Sofa
    sofa_meshes = [
        # Base & Main Cushion
        create_box_mesh("Base", 0.20, 0.00, 0.65, 2.20, 0.42, 1.50, "/Room/Materials/Mat_SofaFabric", "sofa"),
        # Backrest along South edge
        create_box_mesh("Backrest", 0.20, 0.42, 1.32, 2.20, 0.82, 1.50, "/Room/Materials/Mat_SofaFabric"),
        # Left Armrest (West)
        create_box_mesh("Armrest_Left", 0.20, 0.42, 0.65, 0.38, 0.65, 1.32, "/Room/Materials/Mat_SofaFabric"),
        # Right Armrest (East)
        create_box_mesh("Armrest_Right", 2.02, 0.42, 0.65, 2.20, 0.65, 1.32, "/Room/Materials/Mat_SofaFabric"),
        # 2 Throw Cushions
        create_box_mesh("Cushion_Left", 0.45, 0.42, 1.15, 0.85, 0.65, 1.30, "/Room/Materials/Mat_SofaCushion"),
        create_box_mesh("Cushion_Right", 1.55, 0.42, 1.15, 1.95, 0.65, 1.30, "/Room/Materials/Mat_SofaCushion"),
    ]

    # Furniture 5: Closet / Cupboard
    closet_meshes = [
        # Main Cabinet Body
        create_box_mesh("Body", -2.48, 0.00, 0.60, -1.88, 2.10, 1.80, "/Room/Materials/Mat_ClosetBody", "closet"),
        # 2 Brass Vertical Handles on front facing East (+X = -1.88)
        create_box_mesh("Handle_Left", -1.86, 0.95, 1.12, -1.84, 1.25, 1.16, "/Room/Materials/Mat_MetalBrass"),
        create_box_mesh("Handle_Right", -1.86, 0.95, 1.24, -1.84, 1.25, 1.28, "/Room/Materials/Mat_MetalBrass"),
    ]

    # Furniture 6: TV & Media Console
    tv_meshes = [
        # Media Console
        create_box_mesh("Console", 0.50, 0.00, -2.02, 1.90, 0.46, -1.64, "/Room/Materials/Mat_WoodWalnut", "tv_stand"),
        # TV Pedestal Stand
        create_box_mesh("Pedestal_Base", 1.02, 0.46, -1.90, 1.38, 0.48, -1.74, "/Room/Materials/Mat_MetalBlack"),
        create_box_mesh("Pedestal_Stem", 1.18, 0.48, -1.84, 1.22, 0.56, -1.80, "/Room/Materials/Mat_MetalBlack"),
        # TV 55-inch Screen
        create_box_mesh("Screen", 0.59, 0.56, -1.84, 1.81, 1.26, -1.80, "/Room/Materials/Mat_TVScreen", "tv"),
        # TV Slim Bezel Outer Trim
        create_box_mesh("Bezel_Top", 0.58, 1.26, -1.84, 1.82, 1.28, -1.80, "/Room/Materials/Mat_MetalBlack"),
        create_box_mesh("Bezel_Bottom", 0.58, 0.54, -1.84, 1.82, 0.56, -1.80, "/Room/Materials/Mat_MetalBlack"),
        create_box_mesh("Bezel_Left", 0.58, 0.54, -1.84, 0.59, 1.28, -1.80, "/Room/Materials/Mat_MetalBlack"),
        create_box_mesh("Bezel_Right", 1.81, 0.54, -1.84, 1.82, 1.28, -1.80, "/Room/Materials/Mat_MetalBlack"),
    ]

    usda_content = f"""#usda 1.0
(
    defaultPrim = "Room"
    metersPerUnit = 1.0
    upAxis = "Y"
    doc = "Resign Spatial Room Layout & Light Simulation Mock USDZ. Units: Meters (Y-up)."
)

def Xform "Room" (
    kind = "component"
)
{{
    def Scope "Materials"
    {{
{mat_block}
    }}

    def Xform "Structure"
    {{
{"".join(structure_meshes)}
    }}

    def Xform "Openings"
    {{
        def Xform "Window" (
            kind = "subcomponent"
        )
        {{
            custom string resign:opening_type = "window"
            custom float3 resign:facing_normal = (1, 0, 0)
{"".join(window_meshes)}
        }}

        def Xform "Door" (
            kind = "subcomponent"
        )
        {{
            custom string resign:opening_type = "door"
            custom float3 resign:facing_normal = (0, 0, 1)
{"".join(door_meshes)}
        }}
    }}

    def Xform "Furniture"
    {{
        def Xform "Bed" (
            kind = "subcomponent"
        )
        {{
            custom string resign:furniture_type = "bed"
{"".join(bed_meshes)}
        }}

        def Xform "Desk" (
            kind = "subcomponent"
        )
        {{
            custom string resign:furniture_type = "desk"
{"".join(desk_meshes)}
        }}

        def Xform "Chair" (
            kind = "subcomponent"
        )
        {{
            custom string resign:furniture_type = "chair"
{"".join(chair_meshes)}
        }}

        def Xform "Sofa" (
            kind = "subcomponent"
        )
        {{
            custom string resign:furniture_type = "sofa"
{"".join(sofa_meshes)}
        }}

        def Xform "Closet" (
            kind = "subcomponent"
        )
        {{
            custom string resign:furniture_type = "closet"
{"".join(closet_meshes)}
        }}

        def Xform "TV" (
            kind = "subcomponent"
        )
        {{
            custom string resign:furniture_type = "tv"
{"".join(tv_meshes)}
        }}
    }}
}}
"""
    return usda_content

def main():
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    resources_dir = os.path.join(repo_root, "Resign", "Resources")
    os.makedirs(resources_dir, exist_ok=True)

    usda_path = os.path.join(resources_dir, "MockRoom.usda")
    usdz_path = os.path.join(resources_dir, "MockRoom.usdz")

    print(f"Generating USDA scene...")
    usda_content = generate_scene()
    with open(usda_path, "w") as f:
        f.write(usda_content)
    print(f"Wrote USDA to: {usda_path}")

    print(f"Packaging into USDZ with usdzip...")
    cmd = ["usdzip", "-c", "MockRoom.usdz", "MockRoom.usda"]
    res = subprocess.run(cmd, cwd=resources_dir, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"usdzip failed: {res.stderr}", file=sys.stderr)
        sys.exit(1)
    print(f"Successfully created USDZ: {usdz_path}")

    print(f"Validating with usdchecker...")
    chk = subprocess.run(["usdchecker", usdz_path], capture_output=True, text=True)
    print(chk.stdout)
    if chk.returncode != 0 or "Failed!" in chk.stdout:
        print(f"usdchecker reported issues!", file=sys.stderr)
        sys.exit(1)

    print("All validations passed cleanly!")

if __name__ == "__main__":
    main()
