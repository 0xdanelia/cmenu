#!/bin/bash

# print the menu on screen instead of piping the text to another program
SCR=/dev/tty
prs () { printf $@ > /dev/tty; }

# functions to hide cursor to prevent flickering while drawing menu on screen
cursor_hide () { prs '%b' '\e[?25l'; }
cursor_show () { prs '%b' '\e[?25h'; }

prs '\e[s'     # save cursor
prs '\e[?47h'  # save screen
prs '\e[H'     # move cursor to top of screen

# collection for input
INDATA=()

# distinguish whitespace characters for user input
IFS=''

# read piped input
if test ! -t 0; then
	while read -r INLINE; do
		INDATA+=("$INLINE")
	done
fi

# read command line input
for ARG in "$@"
do
	INDATA+=("$ARG")
done

# exit if no data provided
[[ -z $INDATA ]] && echo '' && exit 1

SELECTED_IDX=1  # selected index of the given parameters in $@

SELECTED_COLOR='\e[44m\e[37m'
DEFAULT_COLOR='\e[40m\e[37m'

SEARCH_TEXT=''

# loop until the user presses Enter or ESC
loop=true
while $loop; do
	CURRENT_IDX=0    # index of current parameter
	PREV_IDX=0       # index of previous parameter that matches the search criteria
	PREV_PREV_IDX=0  # index of parameter before PREV_IDX
	MENU_IDX=0       # selected index of the menu drawn on screen
	MENU_PREV=0      # previous index from selected on-screen menu item
	MENU_NEXT=0      # following index from selected on-screen menu item
	NUM_ITEMS=0      # total items in on-screen menu

	cursor_hide      # make cursor invisible until menu is fully printed

	# keep track of screen size to prevent menu from printing off screen
	TCOLS=$(tput cols) && let 'TCOLS-=2'
	TROWS=$(tput lines) && let 'TROWS-=1'

	# loop through each parameter
	for ITEM in "${INDATA[@]}"; do	
		let 'CURRENT_IDX+=1'
		# check if current parameter matches the search string
		if [[ -z $SEARCH_TEXT ||  $(echo "$ITEM" | grep "$SEARCH_TEXT") ]];	then
			let 'NUM_ITEMS+=1'

			# this will trigger one line after printing the selected row
			[[ $MENU_NEXT == -1 ]] && MENU_NEXT=$CURRENT_IDX
			
			# start new line for this menu item
			prs '\n%b>%b' $SELECTED_COLOR $DEFAULT_COLOR
			# check if this item is currently selected
			if [[ $CURRENT_IDX == $SELECTED_IDX ]];	then
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
			prs ' %s\e[K' $(printf '%s' $ITEM | cut -c 1-$TCOLS)
			# reset color to default
			prs '%b' $DEFAULT_COLOR
			# the current values are saved as the previous values
			PREV_ITEM=$ITEM
			PREV_PREV_IDX=$PREV_IDX
			PREV_IDX=$CURRENT_IDX

			# stop printing if screen is full
			[[ $NUM_ITEMS == $TROWS ]] && break
			
		else
			# if the selected item no longer matches an updated search string, select the next available item
			[[ $CURRENT_IDX == $SELECTED_IDX ]] && let 'SELECTED_IDX+=1'
		fi	
	done

	# check if the menu has no items
	if [[ $NUM_ITEMS == 0 ]]; then
		SELECTED_ITEM=''
		SELECTED_IDX=1
		MENU_IDX=1
	# if the selected row is now larger than the total rows after an updated search string, select the last row
	elif [[ $MENU_IDX == 0 ]]; then
		SELECTED_ITEM=$PREV_ITEM
		SELECTED_IDX=$PREV_IDX
		MENU_IDX=$NUM_ITEMS
		MENU_PREV=$PREV_PREV_IDX
		MENU_NEXT=0
		# need to redraw the selected row, but now with highlighting
		prs '\r%b> \e[K%s%b' $SELECTED_COLOR $(printf '%s' $SELECTED_ITEM | cut -c 1-$TCOLS) $DEFAULT_COLOR
	fi

	# move cursor back to top of list
	[[ $NUM_ITEMS > 0 ]] && prs '\e[%iA' $NUM_ITEMS
	
	# print user-typed text for searching list
	prs '\r:%s\e[K' $SEARCH_TEXT

	# make cursor re-appear at end of search string
	cursor_show

	# wait for user to hit a key
	read -sn1 key </dev/tty
	
	case "$key" in
		# special keys will send multiple characters, beginning with this sequence
		($'\033')
			# read the remaining characters for a special key
			read -t.001 -sn2 arrow </dev/tty
			case "$arrow" in
				# up arrow
				('[A'|'OA')
					[[ $MENU_PREV -gt 0 ]] && SELECTED_IDX=$MENU_PREV
				;;
				# down arrow
				('[B'|'OB')
					[[ $MENU_NEXT -gt 0 ]] && SELECTED_IDX=$MENU_NEXT
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
			[[ ! -z $SEARCH_TEXT ]] && SEARCH_TEXT=${SEARCH_TEXT::-1} && prs '\e[0J'
		;;
		# enter
		('')
			loop=false
		;;
		# other chars
		(*)
			SEARCH_TEXT=$SEARCH_TEXT$key
			prs '\e[0J' 
		;;
	esac
done

prs '\e[?47l'  # restore screen
prs '\e[u'     # restore cursor

# print result
echo "$SELECTED_ITEM"
