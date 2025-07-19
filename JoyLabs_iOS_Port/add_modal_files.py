#!/usr/bin/env python3

import os
import sys

def add_files_to_xcode_project():
    """Add the modal files to the Xcode project by copying them to the main source directory"""
    
    # Source files
    modal_file = "JoyLabsNative/Views/Components/QuantitySelectionModal.swift"
    numpad_file = "JoyLabsNative/Views/Components/QuantityNumpad.swift"
    
    # Target directory (where other Swift files are)
    target_dir = "JoyLabsNative/Views"
    
    # Copy files to main Views directory so they get picked up automatically
    modal_target = f"{target_dir}/QuantitySelectionModal.swift"
    numpad_target = f"{target_dir}/QuantityNumpad.swift"
    
    try:
        # Copy modal file
        with open(modal_file, 'r') as src:
            content = src.read()
        with open(modal_target, 'w') as dst:
            dst.write(content)
        print(f"✅ Copied {modal_file} to {modal_target}")
        
        # Copy numpad file
        with open(numpad_file, 'r') as src:
            content = src.read()
        with open(numpad_target, 'w') as dst:
            dst.write(content)
        print(f"✅ Copied {numpad_file} to {numpad_target}")
        
        print("🎉 Modal files successfully added to project!")
        return True
        
    except Exception as e:
        print(f"❌ Error: {e}")
        return False

if __name__ == "__main__":
    success = add_files_to_xcode_project()
    sys.exit(0 if success else 1)
