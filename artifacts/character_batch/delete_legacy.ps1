$root = (Resolve-Path '.').Path
$characters = Join-Path $root 'assets/characters'
$legacyDirectories = @(
    'assets/characters/hero',
    'assets/characters/paladin',
    'assets/characters/py',
    'assets/characters/meshy_adventure',
    'assets/characters/meshy_hero',
    'assets/characters/meshy_hero2',
    'assets/characters/meshy_paladin',
    'assets/characters/meshy_ronin',
    'assets/characters/meshy_samurai',
    'assets/characters/meshy_warrior',
    'assets/characters/tripo_adventure',
    'assets/characters/tripo_black_mage',
    'assets/characters/tripo_butler',
    'assets/characters/tripo_chief_butler',
    'assets/characters/tripo_hiro',
    'assets/characters/tripo_knight',
    'assets/characters/tripo_knight2',
    'assets/characters/tripo_roster',
    'assets/characters/tripo_scholar',
    'assets/characters/tripo_warrior',
    'assets/characters/tripo_white_mage',
    'assets/characters/generated/golden_path_001',
    'assets/characters/generated/golden_path_002',
    'assets/characters/_shared/animations',
    'assets/characters/_shared/master_rig'
)
$legacyFiles = @(
    'assets/characters/base/base.glb',
    'assets/characters/base/base.glb.import',
    'assets/characters/base/base.blend',
    'assets/characters/base/base.blend.import',
    'assets/characters/female/base/female_base.glb',
    'assets/characters/female/base/female_base.glb.import',
    'assets/characters/female/base/female_base.gltf',
    'assets/characters/female/base/female_base.gltf.import',
    'assets/characters/female/base/female_base.bbmodel',
    'assets/characters/test/Meshy_AI_Crimson_Nightblade_0705052047_generate.glb',
    'assets/characters/test/Meshy_AI_Crimson_Nightblade_0705052047_generate.glb.import',
    'assets/characters/test/chibi-figure.glb',
    'assets/characters/test/chibi-figure.glb.import',
    'assets/world_jrpg/explorer_base_1.glb',
    'assets/world_jrpg/explorer_base_1.glb.import',
    'scenes/characters/adventurer_npc.tscn',
    'scenes/characters/tripo_hero_npc.tscn',
    'scenes/characters/tripo_knight_npc.tscn',
    'scenes/characters/tripo_knight_player.tscn',
    'scenes/characters/tripo_roster/adventure.tscn',
    'scenes/characters/tripo_roster/black_mage.tscn',
    'scenes/characters/tripo_roster/butler.tscn',
    'scenes/characters/tripo_roster/chief_butler.tscn',
    'scenes/characters/tripo_roster/hero.tscn',
    'scenes/characters/tripo_roster/knight.tscn',
    'scenes/characters/tripo_roster/knight_player.tscn',
    'scenes/characters/tripo_roster/scholar.tscn',
    'scenes/characters/tripo_roster/warrior.tscn',
    'scenes/characters/tripo_roster/white_mage.tscn',
    'scenes/characters/tripo_roster/golden_path_001.tscn',
    'scenes/characters/tripo_roster/golden_path_002.tscn',
    'scripts/character/adventurer_appearance.gd',
    'scripts/character/adventurer_appearance.gd.uid',
    'scripts/character/adventurer_character.gd',
    'scripts/character/adventurer_character.gd.uid',
    'scripts/character/tripo_hero_character.gd',
    'scripts/character/tripo_hero_character.gd.uid',
    'scripts/character/tripo_knight_character.gd',
    'scripts/character/tripo_knight_character.gd.uid',
    'scripts/character/tripo_roster_import.gd',
    'scripts/character/tripo_roster_import.gd.uid',
    'scripts/character/golden_path_roster_character.gd',
    'scripts/character/golden_path_roster_character.gd.uid',
    'scripts/world_jrpg/verify_adventurer_rig.gd',
    'scripts/world_jrpg/verify_meshy_adventure.gd',
    'scripts/world_jrpg/verify_meshy_hero.gd',
    'scripts/world_jrpg/verify_meshy_hero2.gd',
    'scripts/world_jrpg/verify_meshy_paladin.gd',
    'scripts/world_jrpg/verify_tripo_hero.gd',
    'scripts/world_jrpg/verify_tripo_knight.gd',
    'scripts/world_jrpg/verify_tripo_roster.gd',
    'scripts/world_jrpg/verify_sword_combat.gd',
    'tools/asset_gen/character_pipeline/verify_golden_path.gd',
    'tools/asset_gen/character_pipeline/verify_golden_path.gd.uid',
    'tools/asset_gen/character_pipeline/verify_face_controller.gd',
    'tools/asset_gen/character_pipeline/verify_face_controller.gd.uid',
    'tools/verify_character_phase1.gd',
    'tools/verify_render_character_phase1_5.gd',
    'tools/render_character_phase1.gd'
)
foreach ($relative in $legacyDirectories + $legacyFiles) {
    $target = [System.IO.Path]::GetFullPath((Join-Path $root $relative))
    if (-not $target.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Outside workspace: $target"
    }
    $protected = Join-Path $characters 'tripo'
    if ($target -eq $protected -or $target.StartsWith($protected + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Protected source: $target"
    }
    if (-not (Test-Path -LiteralPath $target)) { continue }
    if ($legacyDirectories -contains $relative) {
        if (-not (Test-Path -LiteralPath $target -PathType Container)) { throw "Expected directory: $target" }
        Remove-Item -LiteralPath $target -Recurse -Force
    } else {
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Expected file: $target" }
        Remove-Item -LiteralPath $target -Force
    }
    Write-Output $relative
}
