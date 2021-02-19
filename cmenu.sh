#!/bin/bash

# print the menu on screen instead of piping the text to another program
SCR=/dev/tty
prs () { printf $@ > /dev/tty ; }

# functions to hide cursor to prevent flickering while drawing menu on screen
cursor_hide () { prs '%b' '\e[?25l'; }
cursor_show () { prs '%b' '\e[?25h'; }

prs '\e[s'     # save cursor
prs '\e[?47h'  # save screen
prs '\e[H'     # move cursor to top of screen

# collection for input
declare -a INDATA
declare -a DATA_INDEXES
declare -a SEARCH_HISTORY

# distinguish whitespace characters for user input
IFS=''

# read piped input
if test ! -t 0; then
	count=0
	while read -r INLINE; do
		INDATA+=("$INLINE")
		DATA_INDEXES+=($count)
		let 'count+=1'
	done
fi

SEARCH_HISTORY=("${DATA_INDEXES[@]}")

# read command line input
for ARG in "$@"
do
	INDATA+=("$ARG")
done

# exit if no data provided
[[ -z $INDATA ]] && echo '' && exit 1

SELECTED_IDX=0    # selected index of the given parameters in $@
SELECTED_ITEM=''  # the menu item to output

SELECTED_COLOR='\e[44m\e[37m'
DEFAULT_COLOR='\e[40m\e[37m'

SEARCH_TEXT=''

REPRINT=true

PRINT_MENU () {
	PREV_IDX=-1      # index of previous parameter that matches the search criteria
	PREV_PREV_IDX=-2 # index of parameter before PREV_IDX
	MENU_PREV=-1     # previous index from selected on-screen menu item
	MENU_NEXT=0      # following index from selected on-screen menu item
	NUM_ITEMS=0      # total items in on-screen menu
	SELECTED=false   # lets us know when the selected item is printed
	cursor_hide      # make cursor invisible until menu is fully printed

	# clear screen
	prs '\e[0J'

	# keep track of screen size to prevent menu from printing off screen
	TCOLS=$(tput cols) && let 'TCOLS-=2'
	TROWS=$(tput lines) && let 'TROWS-=1'

	# loop through each parameter
	for CURRENT_IDX in ${DATA_INDEXES[@]}; do
		ITEM=${INDATA[$CURRENT_IDX]}

		let 'NUM_ITEMS+=1'
		
		# this will trigger one line after printing the selected row
		$SELECTED && [[ $MENU_NEXT == 0 ]] && MENU_NEXT=$CURRENT_IDX

		# if the selected item is filtered out, select the next available item
		! $SELECTED && [[ $CURRENT_IDX -gt $SELECTED_IDX ]] && SELECTED_IDX=$CURRENT_IDX

		# if the selected item and all items after it are filtered out, select the final item
		! $SELECTED && [[ $CURRENT_IDX -eq ${DATA_INDEXES[-1]} ]] && SELECTED_IDX=$CURRENT_IDX
		
		# start new line for this menu item
		prs '\n%b>%b' $SELECTED_COLOR $DEFAULT_COLOR
		# check if this item is currently selected
		if [[ $CURRENT_IDX == $SELECTED_IDX ]];	then
			# set highlighted color
			prs '%b' $SELECTED_COLOR
			# set some useful indexes centered around the selected item
			SELECTED_ITEM=$ITEM
			MENU_PREV=$PREV_IDX
			# this will set MENU_NEXT when printing the following row
			SELECTED=true
		fi		
		# print menu item
		prs ' %s\e[0K' $(printf '%s' $ITEM | cut -c 1-$TCOLS)
		# reset color to default
		prs '%b\e' $DEFAULT_COLOR
		# the current values are saved as the previous values
		PREV_ITEM=$ITEM
		PREV_PREV_IDX=$PREV_IDX
		PREV_IDX=$CURRENT_IDX

		# stop printing if screen is full
		[[ $NUM_ITEMS == $TROWS ]] && break
	done

	# check if the menu has no items
	if [[ $NUM_ITEMS == 0 ]]; then
		SELECTED_ITEM=''
		SELECTED_IDX=0
		MENU_IDX=0
	elif ! $SELECTED; then
		echo "something went wrong"
		read key
	fi

	# move cursor back to top of list
	[[ $NUM_ITEMS > 0 ]] && prs '\e[%iA' $NUM_ITEMS
	
	# print user-typed text for searching list
	prs '\r:%s\e[K' $SEARCH_TEXT

	# make cursor re-appear at end of search string
	cursor_show
}

GET_KEY () {

	# flush stdin
	read -s -t.001 key </dev/tty

	# wait for user to hit a key
	read -sn1 key </dev/tty
	
	case "$key" in
		# special keys will send multiple characters, beginning with this sequence
		($'\033')
			# read the remaining characters for a special key
			read -s -t.001 arrow </dev/tty
			
			case "$arrow" in
				# up arrow
				('[A'|'OA')
					[[ $MENU_PREV -ge 0 ]] && SELECTED_IDX=$MENU_PREV
					REPRINT=true
				;;
				# down arrow
				('[B'|'OB')
					[[ $MENU_NEXT -gt 0 ]] && SELECTED_IDX=$MENU_NEXT
					REPRINT=true
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
			if [[ ! -z $SEARCH_TEXT ]]; then
				SEARCH_TEXT=${SEARCH_TEXT::-1}
				#prs '\e[0J'
				IFS=","
				DATA_INDEXES=( "${SEARCH_HISTORY[@]}"  )
				DATA_INDEXES=( $(SEARCH_FILTER) )
				IFS=''
				REPRINT=true
			fi
		;;
		# enter
		('')
			loop=false
		;;
		# other chars
		(*)
			SEARCH_TEXT=$SEARCH_TEXT$key
			IFS=","
			DATA_INDEXES=( $(SEARCH_FILTER) )
			IFS=''
			REPRINT=true
		;;
	esac
}

SEARCH_FILTER () {
	FILTERED=()

	for idx in ${DATA_INDEXES[@]}; do
		[[ $(echo ${INDATA[$idx]} | grep "$SEARCH_TEXT") ]] && FILTERED+=("$idx,")
	done

	printf '%s' "${FILTERED[@]}"
}

# loop until the user presses Enter or ESC
loop=true

while $loop; do
	$REPRINT && REPRINT=false && PRINT_MENU
	GET_KEY
done

prs '\e[?47l'  # restore screen
prs '\e[u'     # restore cursor

# print result
echo "$SELECTED_ITEM"
