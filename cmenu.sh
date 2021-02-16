#!/bin/bash

# distinguish whitespace characters for user input
IFS=''

# print the menu on screen instead of piping the text to another program
SCR=/dev/tty
prs () { printf $@ > $SCR; }

SELECTED_IDX=1
MENU_IDX=1
MENU_PREV=0
MENU_NEXT=2
SELECTED_COLOR='\e[44m\e[37m'
DEFAULT_COLOR='\e[40m\e[37m'
SEARCH_TEXT=''

loop=true
while $loop
do
# clear screen from cursor downward
prs '\e[0J' 
CURRENT_IDX=0
PREV_IDX=0
NUM_ITEMS=0

for ITEM in "$@"
do	
	let 'CURRENT_IDX+=1'
	if [[ -z $SEARCH_TEXT ||  $(echo "$ITEM" | grep "$SEARCH_TEXT") ]];
	then
		let 'NUM_ITEMS+=1'

		if [[ $MENU_NEXT == 0 ]];
		then
			MENU_NEXT=$CURRENT_IDX
		fi
		
		# print newline and clear contents from screen
		prs '\n'
		# set color of selected item
		if [[ $CURRENT_IDX == $SELECTED_IDX ]];
		then
			prs '%b' $SELECTED_COLOR
			SELECTED_ITEM=$ITEM
			MENU_IDX=$NUM_ITEMS
			MENU_PREV=$PREV_IDX
			MENU_NEXT=0
		fi
		# print menu item
		prs '%s' $ITEM
		# reset color to default
		prs '%b' $DEFAULT_COLOR
		PREV_ITEM=$ITEM
		PREV_IDX=$CURRENT_IDX
	fi
done

if [[ $SELECTED_IDX > $NUM_ITEMS ]];
then
	SELECTED_IDX=$NUM_ITEMS
	MENU_IDX=$NUM_ITEMS
	SELECTED_ITEM=$PREV_ITEM
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
					if [[ $MENU_PREV > 0 ]]; 
					then
						MENU_NEXT=$SELECTED_IDX
						SELECTED_IDX=$MENU_PREV
						MENU_PREV=0
					fi
				;;
				# down arrow
				('[B')
					if [[ $MENU_NEXT > 0 ]];  # down
					then
						MENU_PREV=$SELECTED_IDX
						SELECTED_IDX=$MENU_NEXT
						MENU_NEXT=-1
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
