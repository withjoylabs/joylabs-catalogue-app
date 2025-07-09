#!/usr/bin/env python3
"""
Script to fix Xcode project by removing references to deleted files
and adding references to new SQLite.swift files
"""

import re
import os

def fix_xcode_project():
    project_file = "JoyLabsNative.xcodeproj/project.pbxproj"
    
    # Files to remove (broken references)
    files_to_remove = [
        "CatalogSyncService.swift",
        "SquareSyncCoordinator.swift", 
        "CatalogDatabaseManager.swift",
        "CatalogDatabaseSchema.swift",
        "ResilientDatabaseManager.swift",
        "MockDatabaseManager.swift",
        "EnhancedDatabaseManager.swift"
    ]
    
    # Files to add (new SQLite.swift files)
    files_to_add = [
        "DatabaseBackup.swift",
        "SQLiteSwiftCatalogManager.swift", 
        "DatabaseMigrationService.swift",
        "SQLiteSwiftCatalogSyncService.swift",
        "SQLiteSwiftSyncCoordinator.swift"
    ]
    
    print("🔧 Fixing Xcode project references...")
    
    # Read the project file
    with open(project_file, 'r') as f:
        content = f.read()
    
    # Remove broken file references
    for filename in files_to_remove:
        print(f"❌ Removing references to {filename}")
        
        # Remove PBXBuildFile entries
        content = re.sub(
            rf'[A-F0-9]{{24}} /\* {re.escape(filename)} in Sources \*/ = {{isa = PBXBuildFile; fileRef = [A-F0-9]{{24}} /\* {re.escape(filename)} \*/; }};?\n?',
            '',
            content
        )
        
        # Remove PBXFileReference entries
        content = re.sub(
            rf'[A-F0-9]{{24}} /\* {re.escape(filename)} \*/ = {{isa = PBXFileReference; [^}}]+}};?\n?',
            '',
            content
        )
        
        # Remove from PBXGroup children arrays
        content = re.sub(
            rf'[A-F0-9]{{24}} /\* {re.escape(filename)} \*/,?\n?\s*',
            '',
            content
        )
        
        # Remove from PBXSourcesBuildPhase files arrays
        content = re.sub(
            rf'[A-F0-9]{{24}} /\* {re.escape(filename)} in Sources \*/,?\n?\s*',
            '',
            content
        )
    
    # Clean up any trailing commas in arrays
    content = re.sub(r',(\s*\);)', r'\1', content)
    
    print("✅ Removed all broken file references")
    
    # Write the cleaned project file
    with open(project_file, 'w') as f:
        f.write(content)
    
    print("🎉 Xcode project file cleaned successfully!")
    print("\nNEXT STEPS:")
    print("1. Open Xcode")
    print("2. Manually add the new SQLite.swift files to the project:")
    for filename in files_to_add:
        print(f"   - {filename}")
    print("3. Build the project")

if __name__ == "__main__":
    fix_xcode_project()
