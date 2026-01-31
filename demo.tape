# VHS Demo for autocommit CLI tool
# Prerequisites (run before vhs):
#   1. zig build
#   2. alias ac='autocommit --add --accept --push'
# Generate with: vhs demo.tape

Output demo.gif

# Modern terminal setup matching Ghostty aesthetic
Set Shell "zsh"
Set FontSize 16
Set FontFamily "Hack Nerd Font"
Set Width 1200
Set Height 800
Set Padding 20
Set Margin 20
Set BorderRadius 10
Set TypingSpeed 50ms
Set CursorBlink true

# Theme settings (dark modern terminal)
Set Theme "Argonaut"

# Setup: ensure alias is set
Hide
Type "alias ac='autocommit --add --accept --push'" Sleep 100ms  Enter
Type "alias autocommit='./zig-out/bin/autocommit'" Sleep 100ms  Enter
Type "clear" Enter
Show

# Step 1: Show config
Type "autocommit config show" Sleep 100ms Enter

Sleep 4s
Hide
Type "clear" Enter
Show
# Step 2: Run autocommit interactively
Type "autocommit" Sleep 100ms Enter

Sleep 1500ms

# Respond to prompts
Enter

Sleep 3s

# Show commit message generation
Enter

Sleep 1s

Enter

Sleep 2s

# Step 3: Show the alias tip
Hide
Type "clear" Enter
Show
Type "echo 'alias ac=autocommit --add --accept --push'" Sleep 500ms Enter

# Step 4: Quick demo with alias
Hide
Type "clear" Enter
Show
Type "echo 'Quick workflow with ac alias' && echo 'Creating test.file...' && echo 'Test content' > test.file" Sleep 100ms Enter

Sleep 500ms

Type "echo '' && echo '$ ac' && ac" Sleep 100ms Enter

Sleep 4s

# Show success
Type "clear && echo 'Done! Committed and pushed automatically' && git log --oneline -1" Sleep 100ms Enter

Sleep 1s

# Final
Type "echo '' && echo 'autocommit makes git commits effortless!'" Sleep 100ms Enter

Sleep 2s

