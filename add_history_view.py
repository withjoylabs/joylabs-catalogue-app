#!/usr/bin/env python3

import os
import sys
import uuid

def add_history_view_to_xcode():
    """Add HistoryView.swift to the Xcode project"""

    project_file = "JoyLabs_iOS_Port/JoyLabsNative.xcodeproj/project.pbxproj"

    if not os.path.exists(project_file):
        print(f"Error: {project_file} not found")
        return False

    # Read the project file
    with open(project_file, 'r') as f:
        content = f.read()

    # Generate UUIDs for the new file (using a simple pattern like existing files)
    file_uuid = "A1B2C3D4E5F6789012345855"  # Next in sequence after ScanView
    build_uuid = "A1B2C3D4E5F6789012345856"  # Next in sequence

    file_name = "HistoryView.swift"
    
    # Add file reference (following the same pattern as ScanView.swift)
    file_ref = f'\t\t{file_uuid} /* {file_name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "JoyLabsNative/Views/{file_name}"; sourceTree = "<group>"; }};'

    # Add build file reference
    build_ref = f'\t\t{build_uuid} /* {file_name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_uuid} /* {file_name} */; }};'

    # Find the main JoyLabsNative group and add the file (same as ScanView.swift)
    main_group_pattern = 'A1B2C3D4E5F6789012345689 /* JoyLabsNative */ = {'
    main_group_start = content.find(main_group_pattern)

    if main_group_start == -1:
        print("Error: Could not find JoyLabsNative group")
        return False

    # Find the children array in the main group
    children_start = content.find('children = (', main_group_start)
    children_end = content.find(');', children_start)

    if children_start == -1 or children_end == -1:
        print("Error: Could not find JoyLabsNative group children")
        return False

    # Add file reference to the main group (after ScanView.swift)
    scanview_ref = 'A1B2C3D4E5F6789012345854 /* ScanView.swift */,'
    scanview_pos = content.find(scanview_ref, children_start)
    if scanview_pos != -1:
        insertion_point = scanview_pos + len(scanview_ref)
        new_child_entry = f'\n\t\t\t\t{file_uuid} /* {file_name} */,'
        content = content[:insertion_point] + new_child_entry + content[insertion_point:]
    
    # Add the file reference to PBXFileReference section
    pbx_file_ref_end = content.find('/* End PBXFileReference section */')
    if pbx_file_ref_end != -1:
        content = content[:pbx_file_ref_end] + file_ref + '\n' + content[pbx_file_ref_end:]
    
    # Add build file reference to PBXBuildFile section
    pbx_build_file_end = content.find('/* End PBXBuildFile section */')
    if pbx_build_file_end != -1:
        content = content[:pbx_build_file_end] + build_ref + '\n' + content[pbx_build_file_end:]
    
    # Add to Sources build phase (after ScanView.swift)
    sources_build_phase = content.find('/* Sources */ = {')
    if sources_build_phase != -1:
        files_start = content.find('files = (', sources_build_phase)
        files_end = content.find(');', files_start)
        if files_start != -1 and files_end != -1:
            # Find ScanView.swift in sources and add after it
            scanview_source_ref = 'A1B2C3D4E5F6789012345853 /* ScanView.swift in Sources */,'
            scanview_source_pos = content.find(scanview_source_ref, files_start)
            if scanview_source_pos != -1:
                insertion_point = scanview_source_pos + len(scanview_source_ref)
                new_source_entry = f'\n\t\t\t\t{build_uuid} /* {file_name} in Sources */,'
                content = content[:insertion_point] + new_source_entry + content[insertion_point:]
    
    # Write the updated project file
    with open(project_file, 'w') as f:
        f.write(content)
    
    print(f"Successfully added {file_name} to Xcode project")
    return True

if __name__ == "__main__":
    add_history_view_to_xcode()
