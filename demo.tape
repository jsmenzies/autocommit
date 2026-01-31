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
Type "alias ac='autocommit --add --accept --push'" Enter
Type "alias autocommit='./zig-out/bin/autocommit'" Enter
Type "clear" Enter
Show

Type "autocommit" Sleep 100ms Enter

Sleep 2s

Enter

Sleep 3s

Enter

Sleep 3s

Enter

Sleep 4s

# Step 3: Show the alias tip
Hide
Type "clear" Enter
Show
Type "echo 'alias ac=autocommit --add --accept --push'" Sleep 500ms Enter

# Step 4: Quick demo with alias
Type "echo 'Quick workflow with ac alias" Sleep 100ms Enter
Type "touch test.file" Sleep 100ms Enter

Type "ac" Enter
