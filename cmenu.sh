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
	while read -rs INLINE; do
		INDATA+=("$INLINE")
		DATA_INDEXES+=($count)
		let 'count+=1'
	done
fi

SEARCH_HISTORY=("${DATA_INDEXES[@]}")
PROMPT=":"
nextPrompt=false

# read command line input
for ARG in "$@";
do
	$nextPrompt && PROMPT="$ARG" && nextPrompt=false && continue

	case "$ARG" in
		('-p')
			nextPrompt=true
		;;
		(*)
			prs 'Invalid parameter %s\n' $ARG
			exit 1
		;;
	esac
done

$nextPrompt && prs 'Did not find prompt after "-p"\n' && exit 1

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

	if [[ $NUM_ITEMS -ge 0 ]]; then
		# move cursor to selected item
		prs '\e[%iB' $(( $MENU_IDX + 1 ))
		# reprint selected item with default color
		prs '\r%b>%b %s\e[0K' $SELECTED_COLOR $DEFAULT_COLOR $(PRINT_SELECTED)
		# move cursor back to top of screen
		prs '\e[H'
		# print user-typed text for searching list
		PRINT_SEARCH
	fi
}

SELECT_ITEM () {

	if [[ $NUM_ITEMS -ge 0 ]]; then
		# move cursor to selected item
		prs '\e[%iB' $(( $MENU_IDX + 1 ))
		# reprint selected item with default color
		prs '\r%b> %s\e[0K' $SELECTED_COLOR $(PRINT_SELECTED)
		# move cursor back to top of screen
		prs '\e[H'
		# print user-typed text for searching list
		PRINT_SEARCH
	fi
}

PRINT_SELECTED () {
	[[ $NUM_ITEMS -ge 0 ]] && printf '%s' $SELECTED_ITEM | cut -c 1-$TCOLS
}

PRINT_ITEM () {
	[[ $NUM_ITEMS -ge 0 ]] && printf '%s' $ITEM | cut -c 1-$TCOLS
}

PRINT_SEARCH () {
	width=$(tput cols) && let "width-=${#PROMPT}"
	cursor_hide
	prs '\r%b%s%s\e[K' $DEFAULT_COLOR $PROMPT $(printf '%s' $SEARCH_TEXT | cut -c 1-$width)
	cursor_show
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
			prs ' %s\e[0K' $(PRINT_ITEM)
		else
			prs '%b %s\e[0K' $DEFAULT_COLOR $(PRINT_ITEM)
		fi

		[[ $count == $NUM_ITEMS ]] && break
	done

	# clear rest of screen
	prs '\e[%iC%b\e[0J' $TCOLS $DEFAULT_COLOR

	# move cursor back to top of screen
	prs '\e[H'
	
	# print user-typed text for searching list
	PRINT_SEARCH

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
		# DEL
		($'\x1b[P')
			if [[ ! -z $SEARCH_TEXT ]]; then
				SEARCH_TEXT=''
				PRINT_SEARCH
				DATA_INDEXES=( "${SEARCH_HISTORY[@]}" )
				DESELECT_ITEM
				GET_INDEXES
				REPRINT
			fi
		;;
		# Backspace
		($'\x08'|$'\x7f')
			if [[ ! -z $SEARCH_TEXT ]]; then
				SEARCH_TEXT=${SEARCH_TEXT::-1}
				PRINT_SEARCH
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
	STARTING_SEARCH_TEXT=$SEARCH_TEXT

	SEARCH_AGAIN=true
	while $SEARCH_AGAIN; do
		SEARCH_AGAIN=false

		# compare input against the search string
		for idx in ${DATA_INDEXES[@]}; do
			[[ $(echo ${INDATA[$idx]} | grep "$SEARCH_TEXT") ]] && FILTERED+=($idx)

			# try to detect key presses while filtering
			key=''
			extra=''
			read -s -N1 -t.001 key </dev/tty
			read -s -t.001 extra </dev/tty
			key=$key$extra
			
			case $key in
				# Backspace  # TODO: get this to work consistently
				($'\x08'|$'\x7f'|$'\177')
					if [[ ! -z $SEARCH_TEXT ]]; then
						if [[ $SEARCH_TEXT == $STARTING_SEARCH_TEXT ]]; then
							DATA_INDEXES=( "${SEARCH_HISTORY[@]}" )
							STARTING_SEARCH_TEXT=''
						fi
						SEARCH_TEXT=${SEARCH_TEXT::-1}
						SEARCH_AGAIN=true
						FILTERED=()
						PRINT_SEARCH
						break
					fi
				;;
				# ESC
				($'\x1b')
					loop=false
					SELECTED_ITEM=''
					break
				;;
				# DEL
				($'\x1b[P')
					if [[ ! -z $SEARCH_TEXT ]]; then
						SEARCH_TEXT=''
						DATA_INDEXES=( "${SEARCH_HISTORY[@]}" )
						SEARCH_AGAIN=true
						FILTERED=()
						PRINT_SEARCH
						break
					fi
				;;
				# enter
				($'\x0a')
					loop=false
				;;
				(*)
					# don't wait for filter to finish
					if [[ ${#key} == 1 ]]; then
						SEARCH_TEXT=$SEARCH_TEXT$key
						# start over using updated search string
						SEARCH_AGAIN=true
						FILTERED=()
						PRINT_SEARCH
						break
					fi
				;;
			esac
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

kill $! 2>/dev/null
prs '\e[?47l'  # restore screen
prs '\e[u'     # restore cursor

# print result
echo "$SELECTED_ITEM"
