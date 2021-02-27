#!/bin/bash

IFS=''                     # do not ignore whitespace on input
searchtext=''              # user-typed filter
prompt=': '                # text at top of screen before the search filter
clr_select='\e[30;47m'     # black text with white highlight
clr_default='\e[0m'        # default colors

prs () { printf $@ > /dev/tty ; }       # prevent printing from being piped to another program
cursor_hide () { prs '%b' '\e[?25l'; }
cursor_show () { prs '%b' '\e[?25h'; }
filter_func () { grep -F "$searchtext" ;}

arg_flag=''
for arg in "$@";
do
	if [[ ! -z $arg_flag ]]; then
		case "$arg_flag" in
		('-p')  # set prompt text
			prompt="$arg"
		;;
		('-c')  # set highlight color (using ANSI escape codes)
			clr_select="$arg"
		;;
		(*)
			echo "Could not parse argument $arg_flag"
			exit 1
		;;
		esac

		arg_flag=''
		continue
	fi

	case "$arg" in
	('-p'|'-c')
		arg_flag=$arg
	;;
	('-c1'|'-c2'|'-c3'|'-c4')  # preset custom highlight colors
		[[ "$arg" == "-c1" ]] && clr_select='\e[44;37m'  # white on blue
		[[ "$arg" == "-c2" ]] && clr_select='\e[34;42m'  # blue on green
		[[ "$arg" == "-c3" ]] && clr_select='\e[30;43m'  # black on yellow
		[[ "$arg" == "-c4" ]] && clr_select='\e[37;41m'  # white on red
	;;
	('-i')
		filter_func () { grep -F -i "$searchtext" ;}
	;;
	(*)
		echo "Could not parse argument $arg"
		exit 1
	;;
	esac
done

[[ ! -z $arg_flag ]] && echo "Could not parse argument $arg_flag" && exit 1

# directory to store files so the $filter_proc and $print_proc background shells can communicate
cache_dir=~/.cache/cmenu/active_
# use a unique identifier for this cache so other instances of cmenu do not conflict
cache_ID=$$$(date +%s%N) # process id + seconds + nanoseconds
while [[ -e $cache_dir$cache_ID ]]; do
	cache_ID=$$$(date +%s%N)
done
cache_dir=$cache_dir$cache_ID
mkdir -p $cache_dir
# cache files
index_cache_num=0                      # increment as the filter search string increases
index_file="$cache_dir/cmenu_indexes"  # combine with $index_cache_num to keep track of filtered indexes
select_file="$cache_dir/cmenu_select"  # holds the index of the selected item
menu_file="$cache_dir/cmenu_menu"      # holds the on-screen index of the selected item
start_file="$cache_dir/cmenu_start"    # holds the index of the first item printed on screen

# replace tabs with the appropriate number of spaces
clean_input () {
	result=''
	tabs='    '
	for ((i=0; i<${#inline}; i++)); do
		c=${inline:$i:1}
		case $c in
		# tab
		($'\t')
			result=$result$tabs
			tabs=''
		;;
		(*)
			result=$result$c
			tabs=${tabs::-1}
		;;
		esac
		[[ $tabs == '' ]] && tabs='    '
	done
	inline=$result
}

# read piped input
stdin=()       # strings of input text for displaying
stdin_orig=()  # unaltered input text for outputting
indexes=()  # indexes of menu items  #TODO: since indexes are read from files, do we need this variable?
if test ! -t 0; then
	filename="$index_file$index_cache_num"
	rm $filename 2>/dev/null
	count=0
	while read -rs inline; do
		stdin_orig+=($inline)
		clean_input
		stdin+=($inline)
		indexes+=($count)
		echo "$count" >> $filename
		let 'count+=1'
	done
	echo "done" >> $filename
fi

original_indexes=( ${indexes[@]} )

# Set up the screen
tput smcup     # save current contents of terminal
prs '\e[H\e[J' # move cursor to top of screen and clear it

# important indexes
select_idx=0        # index of selected item in stdin
select_menu_idx=0   # index of selected item on screen
start_menu_idx=0    # index of item in stdin that is first to print on screen
select_item=''      # value of selected item
need_index_refresh=false  # is our indexes() array up to date or not
need_deselect=false       # do we need to remove the highlight from screen

filter_proc=  # pid of background shell that is running the filter
print_proc=   # pid of background shell that is printing the menu on screen

# filter stdin for values that match the search string
filter_search () {
	get_select_index
	get_start_index
	selected=false
	prev_idx=-1
	count=-1
	max_height=$(($(tput lines)-1))
	filename="$index_file$index_cache_num"
	rm $filename 2> /dev/null

	# filter on top of the previously filtered indexes, if possible
	if [[ $index_cache_num -gt 0 ]]; then
		# read from previous cache of indexes
		prev_filename="$index_file$(($index_cache_num-1))"
		cache_done=false
		if [[ -f $prev_filename ]]; then
			while read -rs idx; do
				[[ "$idx" == "done" ]] && cache_done=true && break
				filter_check
			done < $prev_filename
		fi
		# if the previous filter did not finish, continue using stdin
		if ! $cache_done; then
			for (( idx=$(($prev_idx+1)); idx<${#original_indexes[@]}; idx++ )); do
				filter_check
			done
		fi
	else
		# no previous cache so read from original stdin
		for idx in ${original_indexes[@]}; do
			filter_check
		done
	fi
	# used to indicate that the filter finished and was not interrupted
	echo 'done' >> $filename
	# if filter shrinks list past selected item, select the last item
	! $selected && select_idx=$prev_idx && select_menu_idx=$count
	# make sure newly filtered items print on screen
	[[ $select_menu_idx -le $max_height ]] && start_menu_idx=0 ||
	start_menu_idx=$(($select_menu_idx-$max_height+2))
	# store indexes in cache
	save_menu_index
	save_select_index
	save_start_index
}

# see if the item matches on the search text
filter_check () {
	if [[ $(echo ${stdin_orig[$idx]} | filter_func) ]]; then
		let 'count+=1'
		# if filter removes the previously selected item from list, select the next available item instead
		! $selected && [[ $idx -gt $select_idx ]] && select_idx=$idx
		# set some values if the selected item is matched
		[[ $idx == $select_idx ]] && select_menu_idx=$count && selected=true
		 echo $idx >> $filename
		 prev_idx=$idx
	fi
}

# filtering after a backspace, which means the new filter string results have already been cached
filter_prev_search () {
	get_select_index
	count=-1
	prev_idx=-1
	selected=false
	max_height=$(($(tput lines)-1))
	filename="$index_file$index_cache_num"
	next_file="$index_file$(($index_cache_num+1))"
	rm $next_file 2> /dev/null
	cache_done=false
	# the previously filtered indexes don't require re-filtering
	if [[ -f $filename ]]; then
		while read -rs idx; do
			[[ "$idx" == "done" ]] && cache_done=true && break
			let 'count+=1'
			[[ $select_idx -lt 0 ]] && select_idx=$idx
			[[ $idx == $select_idx ]] && select_menu_idx=$count && selected=true
			prev_idx=$idx
		done < $filename
	fi
	# if the filter was previously interrupted, finish filtering on original input
	if ! $cache_done; then
		for (( idx=$(($prev_idx+1)); idx<${#original_indexes[@]}; idx++ )); do
			if [[ $(echo ${stdin_orig[$idx]} | filter_func) ]]; then
				let 'count+=1'				
				[[ $idx == $select_idx ]] && select_menu_idx=$count && selected=true
				 echo $idx >> $filename
				 prev_idx=$idx
			fi
		done
		echo 'done' >> $filename
		# if filter shrinks list past selected item, select the first item
		! $selected && select_idx=$prev_idx && select_menu_idx=$count
		# if the filter results in no valid items, set the indexes to defaults
		[[ $count -lt 0 ]] && select_idx=-1 && select_menu_idx=-1
	fi
	# make sure newly filtered items print on screen
	[[ $select_menu_idx -le $max_height ]] && start_menu_idx=0 ||
	start_menu_idx=$(($select_menu_idx-$max_height+2))
	# cache indexes
	save_menu_index
	save_select_index
	save_start_index
}

# print items on screen
print_menu () {
	get_menu_index
	get_select_index
	get_start_index
	count=-1
	item_width=$(($(tput cols)-2))
	max_height=$(($(tput lines)-1))
	filename="$index_file$index_cache_num"
	cursor_hide
	# move cursor to top of screen
	prs '\e[H'
	# read from file of current indexes
	while read -rs idx; do
		let 'count+=1'
		# when done, clear rest of screen and stop printing
		[[ "$idx" == 'done' ]] && prs '\n%b\e[0J' $clr_default && break
		# skip items that are before the first on-screen item
		[[ $count -lt $start_menu_idx ]] && continue
		# set color for current item
		[[ $count == $select_menu_idx ]] && clr_line=$clr_select || clr_line=$clr_default
		# get value of item
		item="${stdin[$idx]}"
		# if item contains color codes, change the "reset" code to be the currently selected color instead
		item=$(echo -e "$item" | sed "s/\x1b\[0m/\x1b${clr_line:2}/g")
		# trim item to fit on screen and print
		prs '\n%b>%b %s\e[K' $clr_select $clr_line ${item::$item_width}
		# stop printing once bottom of screen is reached
		[[ $(($count-$start_menu_idx+2)) == $(($max_height)) ]] && break
	done < $filename
	# clear the progress bar
	prs '%b\e[\r%iB\e[K' $clr_default $max_height
	# go back to top of screen and print search text
	print_search
}

# print the prompt and user-typed search string
print_search () {
	cursor_hide
	search_width=$(tput cols)
	# replace tabs in the search text with spaces (for math purposes)
	search_field=$(echo $prompt$searchtext | sed 's/\t/    /g')
	# figure out how much of the search bar would end up off-screen
	search_overflow=$((${#search_field}-$search_width+1))
	[[ $search_overflow -lt 0 ]] && search_overflow=0
	# scroll the prompt and search string to the left if needed, so that the cursor is always on screen
	prs '%b\e[H\r%s\e[K' $clr_default $(echo "${search_field:$search_overflow}" | cut -c 1-$search_width)
	# to prevent screen flickering, this is always the last thing we print before showing the cursor again
	cursor_show
}

#TODO: deselect and reselect can be merged to one function
# remove highlighting from selected item
deselect_item () {
	get_menu_index
	get_select_index
	get_start_index
	if [[ $select_menu_idx -ge 0 ]] && [[ $select_idx -ge 0 ]]; then
		item_width=$(($(tput cols)-2))
		cursor_hide
		# move cursor to selected item
		prs '\e[%iB' $(($select_menu_idx-$start_menu_idx+1))
		# reprint selected item with default color
		item="${stdin[$select_idx]}"
		item=$(echo -e "$item" | sed "s/\x1b\[0m/\x1b${clr_default:2}/g")
		prs '\r%b>%b %s\e[0K' $clr_select $clr_default ${item::$item_width}
	fi
	# return cursor to search text
	print_search
}

# highlight the selected item
reselect_item () {
	get_menu_index
	get_select_index
	get_start_index
	if [[ $select_menu_idx -ge 0 ]] && [[ $select_idx -ge 0 ]]; then
		item_width=$(($(tput cols)-2))
		cursor_hide
		# move cursor to selected item
		prs '\e[%iB' $(($select_menu_idx-$start_menu_idx+1))
		# reprint selected item with default color
		item="${stdin[$select_idx]}"
		item=$(echo -e "$item" | sed "s/\x1b\[0m/\x1b${clr_select:2}/g")
		prs '\r%b> %s\e[0K' $clr_select ${item::$item_width}
	fi
	# return cursor to search text
	print_search
}

# get the indexes of all currently filtered items
get_indexes () {
	if $need_index_refresh; then
		filename="$index_file$index_cache_num"
		indexes=()
		while read -rs idx; do
			[[ "$idx" == 'done' ]] && break
			indexes+=($idx)
		done < $filename
		need_index_refresh=false
	fi
}

#TODO: the get/save functions can be consolidated to one function that takes the variable + filename as input
get_menu_index () {
	read -rs select_menu_idx 2>/dev/null < $menu_file
}

save_menu_index () {
	rm $menu_file 2>/dev/null
	echo "$select_menu_idx" > $menu_file
}

get_start_index () {
	read -rs start_menu_idx 2>/dev/null < $start_file
}

save_start_index () {
	rm $start_file 2>/dev/null
	echo "$start_menu_idx" > $start_file
}

get_select_index () {
	read -rs select_idx 2>/dev/null < $select_file
}

save_select_index () {
	rm $select_file 2>/dev/null
	echo "$select_idx" > $select_file
}

# kill background filtering shell and start new one
update_filter () {
	let 'index_cache_num+=1'
	kill $filter_proc 2>/dev/null
	filter_search &
	filter_proc=$!
}

# kill background filtering shell and start new one, but different
revert_filter () {
	let 'index_cache_num-=1'
	kill $filter_proc 2>/dev/null
	filter_prev_search &
	filter_proc=$!
}

# kill background printing shell and start new one
reprint () {
	kill $print_proc 2>/dev/null
	max_height=$(($(tput lines)-1))
	# reset cursor if it was mid-print
	cursor_hide && prs '%b\e[\r%iB\e[K\e[H' $clr_default $max_height
	# if selected item is highlighted, remove highlighting to indicate to user that menu is updating
	$need_deselect && deselect_item && need_deselect=false
	# start background shell
	queue_print &
	print_proc=$!
}

# wait for filtering to finish in the background before printing
queue_print () {
	dots=''
	next_dot=' .'
	dot_time=0
	dot_cycle=1
	# check for filtering in a loop since we can't use "wait" command from the background printing shell
	while [[ ! -z $filter_proc ]] && $(kill -0 $filter_proc 2>/dev/null); do
		# let's not be too hasty
		sleep .01
		# print some 'in progress' dots to tell the user things are working
		let 'dot_time+=1'
		# update dots every 10 iterations of loop
		if [[ $dot_time == 10 ]]; then
			dot_time=0
			# one dot + one space = 2, three dots + three spaces = 6
			if [[ ${#dots} -ge 6 ]]; then
				dots=''
				# after printing dots, overwrite them one at a time for that sleek "in progress" look
				if [[ $dot_cycle == 1 ]]; then
					next_dot='  '
					dot_cycle=0
				else
					next_dot=' .'
					dot_cycle=1
				fi
			fi
			dots=$dots$next_dot
			max_height=$(($(tput lines)-1))
			cursor_hide
			# print dots
			prs '%b\e[\r%iB%s' $clr_default $max_height $dots
			# move cursor back to top of screen
			print_search
		fi
	done
	# once filtering is done we can finally print the menu
	print_menu
}

# Main():
save_select_index
save_menu_index
save_start_index
reprint
loop=true
while $loop; do
	# wait for user input
	read -rs -N 1 key  </dev/tty
	# get additional input for escape characters
	while read -rs -t0 </dev/tty; do
		read -rs -N 1 </dev/tty
		key=$key$REPLY
	done
	# parse input
	case $key in
	#TODO: up and down arrow can probably be merged into one function
	# Up arrow
	($'\x1b[A'|$'\x1bOA')
		# don't do anything if filtering is in progress
		if ! $(kill -0 $filter_proc 2>/dev/null); then
			get_indexes
			get_menu_index
			get_start_index
			# if we aren't at the first item
			if [[ $select_menu_idx -gt 0 ]]; then
				max_height=$(($(tput lines)-3))
				# if scrolling, don't need to remove highlighting fronm top row
				[[ $select_menu_idx -lt $(($start_menu_idx+1)) ]] || deselect_item
				let 'select_menu_idx-=1'
				save_menu_index
				select_idx=${indexes[$select_menu_idx]}
				save_select_index
				# if scrolling, need to reprint the whole screen
				if [[ $select_menu_idx -lt $start_menu_idx ]]; then
					let 'start_menu_idx-=1'
					save_start_index
					reprint
				else
					# if not scrolling, just re-apply highlighting
					wait $print_proc
					reselect_item
				fi
			fi
		fi
	;;
	# Down arrow
	($'\x1b[B'|$'\x1bOB')
		# don't do anything if filtering is in progress
		if ! $(kill -0 $filter_proc 2>/dev/null); then
			get_indexes
			get_menu_index
			get_start_index
			# if we aren't at the last item
			if [[ $select_menu_idx -lt $((${#indexes[@]}-1)) ]]; then
				max_height=$(($(tput lines)-3))
				# if scrolling, don't need to remove highlighting from bottom row
				[[ $select_menu_idx -gt $(($start_menu_idx+$max_height-1)) ]] || deselect_item
				let 'select_menu_idx+=1'
				save_menu_index
				select_idx=${indexes[$select_menu_idx]}
				save_select_index
				# if scrolling, need to reprint the whole screen
				if [[ $select_menu_idx -gt $(($start_menu_idx+$max_height)) ]]; then
					let 'start_menu_idx+=1'
					save_start_index
					# since menu prints top-down, update the bottom selected item first so we can see it
					kill $print_proc 2>/dev/null
					prs '\e[H'
					reselect_item
					reprint
				else
					# if not scrolling, just re-apply highlighting
					wait $print_proc
					reselect_item
				fi
			fi
		fi
	;;
	# ESC
	($'\x1b')
		# stop the presses and output the empty string
		loop=false
		select_item=''
	;;
	# Backspace
	($'\x7f'|'\b')
		# only backspace if there is something to backspace
		if [[ ! -z $searchtext ]]; then 
			searchtext="${searchtext::-1}"
			need_index_refresh=true
			need_deselect=true
			revert_filter
			reprint
		fi
	;;
	# Enter
	($'\n')
		# wait for any filtering to finish and output the selected result
		loop=false
		wait $filter_proc
		get_select_index
		[[ $select_idx -ge 0 ]] && select_item="${stdin_orig[$select_idx]}"
	;;
	# Typed characters to apply to search text
	(*)
		# make sure it is not a control character (except tabs are cool)
		if [[ ! -z $key ]] && [[ $key == $'\t' ]] || [[ ! $key =~ [[:cntrl:]] ]]; then
			searchtext="$searchtext$key"
			need_index_refresh=true
			need_deselect=true
			update_filter
			reprint
		fi
	;;
	esac
done

# kill any in-progress background shells
kill $filter_proc 2>/dev/null
kill $print_proc 2>/dev/null

# start background shell to clear old cache files
rm -rf $cache_dir &

#TODO: catch CTRL+C (and other kill commands) and make sure my background shells are stopped

# restore previous contents of terminal if possible, otherwise clear screen
tput rmcup || prs '\e[H\e[J'

# print the results to stdout
echo -e "$select_item"
