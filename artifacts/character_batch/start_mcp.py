import bpy
import sys
sys.path.insert(0, r'C:/Users/nomur/AppData/Roaming/Blender Foundation/Blender/5.1/scripts/addons')
import addon
if not hasattr(bpy.types.Scene, 'blendermcp_port'):
    addon.register()
if not getattr(bpy.types, 'blendermcp_server', None):
    bpy.types.blendermcp_server = addon.BlenderMCPServer(port=9876)
if not bpy.types.blendermcp_server.running:
    bpy.types.blendermcp_server.start()
