# cmenu
Display an interactive menu and print the selected item to stdout. This is designed to be an alternative to dmenu for command line tools, or for systems that do not utilize a display manager or desktop environment. Written in bash with no external dependencies.

<img src="https://i.imgur.com/JUgBHL7.gif">


### What it does

cmenu reads from stdin and builds a menu from the results. For example, each line of a file would be a different item in the menu. You can navigate the menu using the up and down arrow keys. You can also filter the contents of the menu by typing. Any item that does not pass a `grep` on the filter is hidden from the menu.

Pressing enter will select the highlighted menu item and print the contents to stdout. Pressing ESC will exit and print the empty string.

This output can be piped into other programs or captured as a variable in a script to be parsed elsewhere.

### Installation

cmenu is just a single bash script. You could just copy/paste the raw text straight from github if you wanted to.

To install cmenu in `/usr/local/bin` so you can call it from anywhere, clone the repository and run the install script:
```
git clone https://0xdanelia/cmenu
cd cmenu
./install.sh
```

### Customization

Piped input is used to build the contents of the menu. Some command line arguments can be used to customize the menu:

`cmenu -i`  Use case-insensitive filtering.

`cmenu -p [PROMPT]`  Display "PROMPT" at the top of the menu. Default value is ":"

`cmenu -c1`  Change the menu highlight colors to white text on blue background.

`cmenu -c2`  Change the menu highlight colors to blue text on green background.

`cmenu -c3`  Change the menu highlight colors to black text on yellow background.

`cmenu -c4`  Change the menu highlight colors to white text on red background.

`cmenu -c [COLOR]`  Change the menu highlight color to the ANSI code specified as "COLOR".
