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

KEYFILE="~.cmenu"

# collection for input
declare -a INDATA
declare -a DATA_INDEXES
declare -a SEARCH_HISTORY

# distinguish whitespace characters for user input
IFS=''

# read piped input
if test ! -t 0; then
	count=0
	while read -rs INLINE; do
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
PREV_ITEM=''
NEXT_ITEM=''
PREV_IDX=-1       # index of previous parameter that matches the search criteria
PREV_PREV_IDX=-2  # index of parameter before PREV_IDX
MENU_PREV=-1      # previous index from selected on-screen menu item
MENU_NEXT=0       # following index from selected on-screen menu item
NUM_ITEMS=0       # total items in on-screen menu

SELECTED_COLOR='\e[44m\e[37m'
DEFAULT_COLOR='\e[40m\e[37m'

SEARCH_TEXT=''

DESELECT_ITEM () {

	# move cursor to selected item
	prs '\e[%iB' $(( $MENU_IDX + 1 ))
	# reprint selected item with default color
	prs '\r%b>%b %s\e[0K' $SELECTED_COLOR $DEFAULT_COLOR $SELECTED_ITEM
	# move cursor back to top of screen
	prs '\e[H'
	# print user-typed text for searching list
	prs '\r%b:%s\e[K' $DEFAULT_COLOR $SEARCH_TEXT
}

SELECT_ITEM () {

	# move cursor to selected item
	prs '\e[%iB' $(( $MENU_IDX + 1 ))
	# reprint selected item with default color
	prs '\r%b> %s\e[0K' $SELECTED_COLOR $SELECTED_ITEM
	# move cursor back to top of screen
	prs '\e[H'
	# print user-typed text for searching list
	prs '\r%b:%s\e[K' $DEFAULT_COLOR $SEARCH_TEXT
}

PRINT_MENU () {

	# hide cursor to prevent flickering while printing
	cursor_hide

	# keep track of screen width to prevent word-wrap
	TCOLS=$(tput cols) && let 'TCOLS-=2'
	count=-1
	
	# loop through each parameter
	for CURRENT_IDX in ${DATA_INDEXES[@]}; do
		ITEM=${INDATA[$CURRENT_IDX]}
		let 'count+=1'

		prs '\n%b>' $SELECTED_COLOR
		if [[ $CURRENT_IDX == $SELECTED_IDX ]]; then
			prs ' %s\e[0K' $(printf '%s' $ITEM | cut -c 1-$TCOLS)
		else
			prs '%b %s\e[0K' $DEFAULT_COLOR $(printf '%s' $ITEM | cut -c 1-$TCOLS)
		fi

		[[ $count == $NUM_ITEMS ]] && break
	done

	# clear rest of screen
	prs '\e[%iC%b\e[0J' $TCOLS $DEFAULT_COLOR

	# move cursor back to top of screen
	prs '\e[H'
	
	# print user-typed text for searching list
	prs '\r%b:%s\e[K' $DEFAULT_COLOR $SEARCH_TEXT

	# make cursor re-appear at end of search string
	cursor_show
}

GET_INDEXES () {
	PREV_ITEM=''
	NEXT_ITEM=''
	PREV_IDX=-1      # index of previous parameter that matches the search criteria
	PREV_PREV_IDX=-2 # index of parameter before PREV_IDX
	MENU_PREV=-1     # previous index from selected on-screen menu item
	MENU_NEXT=0      # following index from selected on-screen menu item
	NUM_ITEMS=-1     # total items in on-screen menu
	SELECTED=false   # lets us know when the selected item is printed

	# keep track of screen height to prevent menu from printing off screen
	TROWS=$(tput lines) && let 'TROWS-=2'

	# loop through each parameter
	for CURRENT_IDX in ${DATA_INDEXES[@]}; do
		ITEM=${INDATA[$CURRENT_IDX]}

		let 'NUM_ITEMS+=1'
		
		# this will trigger one line after printing the selected row
		$SELECTED && [[ $MENU_NEXT == 0 ]] && MENU_NEXT=$CURRENT_IDX && NEXT_ITEM=$ITEM

		# if the selected item is filtered out, select the next available item
		! $SELECTED && [[ $CURRENT_IDX -gt $SELECTED_IDX ]] && SELECTED_IDX=$CURRENT_IDX

		# if the selected item and all items after it are filtered out, select the final item
		! $SELECTED && [[ $CURRENT_IDX -eq ${DATA_INDEXES[-1]} ]] && SELECTED_IDX=$CURRENT_IDX
		
		# check if this item is currently selected
		if [[ $CURRENT_IDX == $SELECTED_IDX ]];	then
			# set some useful indexes centered around the selected item
			SELECTED_ITEM=$ITEM
			MENU_IDX=$NUM_ITEMS
			MENU_PREV=$PREV_IDX
			# this will set MENU_NEXT when printing the following row
			SELECTED=true
		fi		
		# the current values are saved as the previous values
		PREV_ITEM=$ITEM
		PREV_PREV_IDX=$PREV_IDX
		PREV_IDX=$CURRENT_IDX

		# stop printing if screen is full
		[[ $NUM_ITEMS == $TROWS ]] && break
	done

	# check if the menu has no items
	if [[ $NUM_ITEMS == -1 ]]; then
		SELECTED_ITEM=''
		SELECTED_IDX=0
		MENU_IDX=0
	fi
}

GET_KEY () {

	# flush stdin
	read -s -t.001 stdin </dev/tty

	# wait for user to hit a key
	read -sn1 key </dev/tty

	# read the remaining characters for a special key
	read -s -t.001 extra </dev/tty

	key=$key$extra
	
	case "$key" in
		#up arrow
		($'\x1b[A'|$'\x1bOA')
			if [[ $MENU_IDX -gt 0 ]]; then
				wait $!
				DESELECT_ITEM
				let 'MENU_IDX-=1'
				SELECTED_IDX=${DATA_INDEXES[$MENU_IDX]}
				SELECTED_ITEM=${INDATA[$SELECTED_IDX]}
				SELECT_ITEM
			fi
		;;
		# down arrow
		($'\x1b[B'|$'\x1bOB')
			if [[ $MENU_IDX -lt $NUM_ITEMS ]]; then
				wait $!
				DESELECT_ITEM
				let 'MENU_IDX+=1'
				SELECTED_IDX=${DATA_INDEXES[$MENU_IDX]}
				SELECTED_ITEM=${INDATA[$SELECTED_IDX]}
				SELECT_ITEM
			fi
		;;
		# ESC
		($'\x1b')
			loop=false
			SELECTED_ITEM=''
		;;
		# Backspace
		($'\x08'|$'\x7f')
			if [[ ! -z $SEARCH_TEXT ]]; then
				SEARCH_TEXT=${SEARCH_TEXT::-1}
				prs '\r%b:%s\e[K' $DEFAULT_COLOR $SEARCH_TEXT
				DATA_INDEXES=( "${SEARCH_HISTORY[@]}" )
				DESELECT_ITEM
				SEARCH_FILTER
				GET_INDEXES
				REPRINT
			fi
		;;
		# enter
		('')
			loop=false
		;;
		# other chars
		(*)
			if [[ ${#key} == 1 ]]; then
				SEARCH_TEXT=$SEARCH_TEXT$key
				prs '%s' $key
				DESELECT_ITEM
				SEARCH_FILTER
				GET_INDEXES
				REPRINT
			fi
		;;
	esac
}

REPRINT () {
	kill $! 2>/dev/null
	PRINT_MENU &
}

SEARCH_FILTER () {

	# list of indexes to return
	FILTERED=()

	SEARCH_AGAIN=true
	while $SEARCH_AGAIN; do
		SEARCH_AGAIN=false

		# compare input against the search string
		for idx in ${DATA_INDEXES[@]}; do
			[[ $(echo ${INDATA[$idx]} | grep "$SEARCH_TEXT") ]] && FILTERED+=($idx) && count+=1

			# try to detect key presses while filtering
			key=''
			extra=''
			read -sn1 -t.001 key </dev/tty
			read -s -t.001 extra </dev/tty
			key=$key$extra

			case "$key" in
				# Backspace
				($'\x08'|$'\x7f')
					if [[ ! -z $SEARCH_TEXT ]]; then
						SEARCH_TEXT=${SEARCH_TEXT::-1}
						DATA_INDEXES=( "${SEARCH_HISTORY[@]}" )
						DESELECT_ITEM
						SEARCH_FILTER
						GET_INDEXES
						REPRINT
					fi
				;;
				(*)
					# don't wait for filter to finish
					if [[ ${#key} == 1 ]]; then
						SEARCH_TEXT=$SEARCH_TEXT$key
						# start over using updated search string
						SEARCH_AGAIN=true
						key=''
						extra=''
						FILTERED=()
						break
					fi
				;;
			esac
			prs '\r%b:%s\e[K' $DEFAULT_COLOR $SEARCH_TEXT
		done
	done
	# now we use the filtered list to display and select items
	DATA_INDEXES=( ${FILTERED[@]} )
}

# loop until the user presses Enter or ESC
loop=true
GET_INDEXES
PRINT_MENU
while $loop; do
	GET_KEY
done

prs '\e[?47l'  # restore screen
prs '\e[u'     # restore cursor

# print result
echo "$SELECTED_ITEM"
