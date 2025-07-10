#!/usr/bin/env python3

import os
import sys

def add_files_to_xcode_project():
    """Add the new database files to the Xcode project"""
    
    # Files to add
    files_to_add = [
        "JoyLabsNative/Core/Database/CatalogTableDefinitions.swift",
        "JoyLabsNative/Core/Database/CatalogTableCreator.swift", 
        "JoyLabsNative/Core/Database/CatalogObjectInserters.swift"
    ]
    
    project_file = "JoyLabsNative.xcodeproj/project.pbxproj"
    
    if not os.path.exists(project_file):
        print(f"Error: {project_file} not found")
        return False
        
    # Read the project file
    with open(project_file, 'r') as f:
        content = f.read()
    
    # Generate UUIDs for the new files (simple approach)
    import uuid
    
    new_entries = []
    file_refs = []
    
    for file_path in files_to_add:
        file_name = os.path.basename(file_path)
        file_uuid = str(uuid.uuid4()).replace('-', '').upper()[:24]
        build_uuid = str(uuid.uuid4()).replace('-', '').upper()[:24]
        
        # Add file reference
        file_ref = f'\t\t{file_uuid} /* {file_name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {file_name}; sourceTree = "<group>"; }};'
        new_entries.append(file_ref)
        file_refs.append(file_uuid)
        
        # Add build file reference
        build_ref = f'\t\t{build_uuid} /* {file_name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_uuid} /* {file_name} */; }};'
        new_entries.append(build_ref)
    
    # Find the Database group and add files
    database_group_start = content.find('/* Database */ = {')
    if database_group_start == -1:
        print("Error: Could not find Database group")
        return False
    
    # Find the children array in the Database group
    children_start = content.find('children = (', database_group_start)
    children_end = content.find(');', children_start)
    
    if children_start == -1 or children_end == -1:
        print("Error: Could not find Database group children")
        return False
    
    # Add file references to the Database group
    children_content = content[children_start:children_end]
    for file_uuid in file_refs:
        file_name = next(f for f in files_to_add if file_uuid in str(uuid.uuid4()))
        file_name = os.path.basename(file_name) if file_name else "Unknown"
        children_content += f'\n\t\t\t\t{file_uuid} /* {file_name} */,'
    
    # Replace the children section
    content = content[:children_start] + children_content + content[children_end:]
    
    # Add the new entries to the file references section
    pbx_file_ref_start = content.find('/* Begin PBXFileReference section */')
    pbx_file_ref_end = content.find('/* End PBXFileReference section */')
    
    if pbx_file_ref_start != -1 and pbx_file_ref_end != -1:
        file_ref_section = content[pbx_file_ref_start:pbx_file_ref_end]
        for entry in new_entries:
            if 'PBXFileReference' in entry:
                file_ref_section += '\n' + entry
        content = content[:pbx_file_ref_start] + file_ref_section + content[pbx_file_ref_end:]
    
    # Add build file references
    pbx_build_file_start = content.find('/* Begin PBXBuildFile section */')
    pbx_build_file_end = content.find('/* End PBXBuildFile section */')
    
    if pbx_build_file_start != -1 and pbx_build_file_end != -1:
        build_file_section = content[pbx_build_file_start:pbx_build_file_end]
        for entry in new_entries:
            if 'PBXBuildFile' in entry:
                build_file_section += '\n' + entry
        content = content[:pbx_build_file_start] + build_file_section + content[pbx_build_file_end:]
    
    # Write the updated project file
    with open(project_file, 'w') as f:
        f.write(content)
    
    print("Successfully added files to Xcode project")
    return True

if __name__ == "__main__":
    add_files_to_xcode_project()
