
#  deletes everything in tmp folder apart from two selectred dirs, useful for testing
#  copies a scrit  dry-run.vnow.rb from debug folder (not used now)

SOURCE_FILE="debug/dry-run.vnow.rb"
DESTINATION_DIR="."
PARENT_DIR="tmp"
EXCLUDE_DIR1="burntsushi"
EXCLUDE_DIR2="tokio-rs" # Add your second directory to exclude here

# Check if source file exists
if [ ! -f "$SOURCE_FILE" ]; then
    echo "Error: Source file '$SOURCE_FILE' does not exist."
    exit 1
fi

# Check if destination directory exists, create if not
if [ ! -d "$DESTINATION_DIR" ]; then
    echo "Creating destination directory '$DESTINATION_DIR'..."
    mkdir -p "$DESTINATION_DIR"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create destination directory."
        exit 1
    fi
fi

# Copy the file
echo "Copying '$SOURCE_FILE' to '$DESTINATION_DIR'..."
cp "$SOURCE_FILE" "$DESTINATION_DIR"
if [ $? -ne 0 ]; then
    echo "Error: Failed to copy file."
    exit 1
fi

# Check if parent directory exists
if [ ! -d "$PARENT_DIR" ]; then
    echo "Error: Parent directory '$PARENT_DIR' does not exist."
    exit 1
fi

# Delete all directories in directory_c except the excluded directories
echo "Deleting all directories in '$PARENT_DIR' except '$EXCLUDE_DIR1' and '$EXCLUDE_DIR2'..."

# Change to the parent directory
cd "$PARENT_DIR" || { echo "Error: Could not change to directory '$PARENT_DIR'"; exit 1; }

# Find all directories (not files) in the current directory and loop through them
for dir in */; do
    # Remove trailing slash
    dir=${dir%/}

    # Skip the excluded directories
    if [ "$dir" != "$EXCLUDE_DIR1" ] && [ "$dir" != "$EXCLUDE_DIR2" ]; then
        echo "Deleting directory: $dir"
        rm -rf "$dir"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to delete directory '$dir'."
            exit 1
        fi
    else
        echo "Keeping directory: $dir"
    fi
done

echo "All operations completed successfully."
