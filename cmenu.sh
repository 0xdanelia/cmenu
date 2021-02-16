#!/bin/bash

# distinguish whitespace characters for user input
IFS=''

# print the menu on screen instead of piping the text to another program
SCR=/dev/tty
prs () { printf $@ > $SCR; }

SELECTED_IDX=1  # selected index of the given parameters in $@
MENU_IDX=1      # selected index of the menu drawn on screen

SELECTED_COLOR='\e[44m\e[37m'
DEFAULT_COLOR='\e[40m\e[37m'

SEARCH_TEXT=''

# loop until the user presses Enter or ESC
loop=true
while $loop
do
# clear screen from cursor downward
prs '\e[0J' 
CURRENT_IDX=0  # index of current parameter
PREV_IDX=0     # index of previous parameter
MENU_PREV=0    # previous index from selected on-screen menu item
MENU_NEXT=0    # following index from selected on-screen menu item
NUM_ITEMS=0    # total items in on-screen menu

# loop through each parameter
for ITEM in "$@"
do	
	let 'CURRENT_IDX+=1'
	# check if current parameter matches the search string
	if [[ -z $SEARCH_TEXT ||  $(echo "$ITEM" | grep "$SEARCH_TEXT") ]];
	then
		let 'NUM_ITEMS+=1'

		# this will trigger one line after printing the selected row
		if [[ $MENU_NEXT == -1 ]];
		then
			MENU_NEXT=$CURRENT_IDX
		fi

		# start new line for this menu item
		prs '\n'
		
		# check if this item is currently selected
		if [[ $CURRENT_IDX == $SELECTED_IDX ]];
		then
			# set highlighted color
			prs '%b' $SELECTED_COLOR
			# set some useful indexes centered around the selected item
			SELECTED_ITEM=$ITEM
			MENU_IDX=$NUM_ITEMS
			MENU_PREV=$PREV_IDX
			# this will set MENU_NEXT when printing the following row
			MENU_NEXT=-1
		fi
		# print menu item
		prs '%s' $ITEM
		# reset color to default
		prs '%b' $DEFAULT_COLOR
		# the current values are saved as the previous values
		PREV_ITEM=$ITEM
		PREV_IDX=$CURRENT_IDX
	else
		# if the argument does not match the search string
		if [[ $CURRENT_IDX == $SELECTED_IDX ]];
		then
			# if the selected item no longer matches an updated search string, select the next available item
			let 'SELECTED_IDX+=1'
		fi
	fi
done

# if the selected row is now larger than the total rows after an updated search string, select the last row
if [[ $SELECTED_IDX > $NUM_ITEMS ]];
then
	SELECTED_ITEM=$PREV_ITEM
	SELECTED_IDX=$PREV_IDX
	MENU_IDX=$NUM_ITEMS
	MENU_NEXT=0
	# need to redraw the selected row, but now with highlighting
	prs '\r%b%s%b' $SELECTED_COLOR $SELECTED_ITEM $DEFAULT_COLOR
fi

	# move cursor back to top of list
	prs '\e[%iA\r' $NUM_ITEMS
	# print user-typed text for searching list
	prs '%s\e[K' $SEARCH_TEXT

	# wait for user to hit a key
	read -sn1 key

	case "$key" in
		# special keys will send multiple characters, beginning with this sequence
		($'\033')
			# read the remaining characters for a special key
			read -t.001 -sn2 arrow
			case "$arrow" in
				# up arrow
				('[A')
					if [[ $MENU_PREV -gt 0 ]]; 
					then
						SELECTED_IDX=$MENU_PREV
					fi
				;;
				# down arrow
				('[B')
					if [[ $MENU_NEXT -gt 0 ]];  # down
					then
						SELECTED_IDX=$MENU_NEXT
					fi
				;;
				# ESC
				('')
					loop=false
					SELECTED_ITEM=''
				;;
			esac
		;;
		# Backspace
		($'\x7f')
			if [[ ! -z $SEARCH_TEXT ]]
			then
				SEARCH_TEXT=${SEARCH_TEXT::-1}
			fi
		;;
		# enter
		('')
			loop=false
		;;
		# other chars
		(*)
			SEARCH_TEXT="$SEARCH_TEXT$key"
		;;
	esac
done

# clear menu from screen
prs '\r\e[0J'

# print result
echo "$SELECTED_ITEM"
