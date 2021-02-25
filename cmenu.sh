#!/bin/bash

prs () { printf $@ > /dev/tty ; }       # prevent printing from being piped to another program
cursor_hide () { prs '%b' '\e[?25l'; }
cursor_show () { prs '%b' '\e[?25h'; }

# directory to store files so the $filter_proc and $print_proc background shells can communicate
cache_dir=~/.cache/cmenu/active_
# use a unique identifier for this cache so other instances of cmenu do not conflict
cache_ID=$$$(date +%s%N) # process id + seconds + nanoseconds
while [[ -e $cache_dir$cache_ID ]]; do
	cache_ID=$$$(date +%s%N)
done
cache_dir=$cache_dir$cache_ID
mkdir -p $cache_dir
# old cache directories are flagged for deletion 
cache_to_delete_dir=~/.cache/cmenu/to_delete_
# cache files
index_cache_num=0                      # increment as the filter search string increases
index_file="$cache_dir/cmenu_indexes"  # combine with $index_cache_num to keep track of filtered indexes
select_file="$cache_dir/cmenu_select"  # holds the index of the selected item
menu_file="$cache_dir/cmenu_menu"      # holds the on-screen index of the selected item
start_file="$cache_dir/cmenu_start"    # holds the index of the first item printed on screen

stdin=()    # strings of input text
indexes=()  # indexes of menu items  #TODO: since indexes are read from files, do we need this variable?
# read piped input
if test ! -t 0; then
	filename="$index_file$index_cache_num"
	rm $filename 2>/dev/null
	count=0
	while read -rs inline; do
		stdin+=("$inline")
		indexes+=($count)
		echo "$count" >> $filename
		let 'count+=1'
	done
	echo "done" >> $filename
fi

#TODO: read ARGS for special options
# -p  set custom prompt
# -i  use case-insensitive filtering
# -c  set highlight color (possibly?)
# -l  set max menu rows to display on screen
# -s  display menu in-line instead of clearing terminal screen first

original_indexes=( ${indexes[@]} )

#TODO: move useful cursor commands to functions or variables so I don't have to keep looking them up
#prs '\e[s'     # save cursor
#prs '\e[?47h'  # save screen
tput smcup     # save current contents of terminal
prs '\e[H\e[J' # move cursor to top of screen and clear it

IFS=''
searchtext=''  # user-typed filter
prompt=':'

select_idx=0
select_menu_idx=0
start_menu_idx=0
select_item=''
need_index_refresh=false

clr_select='\e[44m\e[37m'
clr_default='\e[40m\e[37m'

filter_proc=  # pid of background shell that is running the filter
print_proc=   # pid of background shell that is printing the menu on screen

filter_search () {
	get_select_index
	get_start_index
	selected=false
	prev_idx=-1
	count=-1
	max_height=$(($(tput lines)-1))
	filename="$index_file$index_cache_num"
	rm $filename 2> /dev/null
	
	if [[ $index_cache_num -gt 0 ]]; then
		# read from previous cache of indexes
		prev_filename="$index_file$(($index_cache_num-1))"
		cache_done=false
		if [[ -f $prev_filename ]]; then
			while read idx; do
				[[ "$idx" == "done" ]] && cache_done=true && break
				filter_check
			done < $prev_filename
		fi
		# if the filter was interrupted, finish filtering on original input
		if ! $cache_done; then
			for (( idx=$(($prev_idx+1)); idx<${#original_indexes[@]}; idx++ )); do
				filter_check
			done
		fi
	else
		# no previous cache so read from original input
		for idx in ${original_indexes[@]}; do
			filter_check
		done
	fi

	echo 'done' >> $filename

	# if filter shrinks list past selected item, select the last item
	! $selected && select_idx=$prev_idx && select_menu_idx=$count

	# make sure newly filtered items print on screen
	[[ $select_menu_idx -le $max_height ]] && start_menu_idx=0 ||
	start_menu_idx=$(($select_menu_idx-$max_height+2))

	save_menu_index
	save_select_index
	save_start_index
}

filter_check () {
	if [[ $(echo ${stdin[$idx]} | grep "$searchtext") ]]; then
		let 'count+=1'
		# if filter removes selected item from list, select the next available item
		! $selected && [[ $idx -gt $select_idx ]] && select_idx=$idx
		
		[[ $idx == $select_idx ]] && select_menu_idx=$count && selected=true
		 echo $idx >> $filename
		 prev_idx=$idx
	fi
}

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
	if [[ -f $filename ]]; then
		while read idx; do
			[[ "$idx" == "done" ]] && cache_done=true && break
			let 'count+=1'
			[[ $select_idx -lt 0 ]] && select_idx=$idx
			[[ $idx == $select_idx ]] && select_menu_idx=$count && selected=true
			prev_idx=$idx
		done < $filename
	fi
	# if the filter was interrupted, finish filtering on original input
	if ! $cache_done; then
		for (( idx=$(($prev_idx+1)); idx<${#original_indexes[@]}; idx++ )); do
			if [[ $(echo ${stdin[$idx]} | grep "$searchtext") ]]; then
				let 'count+=1'				
				[[ $idx == $select_idx ]] && select_menu_idx=$count && selected=true
				 echo $idx >> $filename
				 prev_idx=$idx
			fi
		done
		echo 'done' >> $filename
		# if filter shrinks list past selected item, select the first item
		! $selected && select_idx=$prev_idx && select_menu_idx=$count
		[[ $count -lt 0 ]] && select_idx=-1 && select_menu_idx=-1
	fi

	# make sure newly filtered items print on screen
	[[ $select_menu_idx -le $max_height ]] && start_menu_idx=0 ||
	start_menu_idx=$(($select_menu_idx-$max_height+2))

	save_menu_index
	save_select_index
	save_start_index
}

print_menu () {
	get_menu_index
	get_select_index
	get_start_index
	count=-1
	item_width=$(($(tput cols)-2))
	max_height=$(($(tput lines)-1))
	filename="$index_file$index_cache_num"
	
	cursor_hide
	prs '\e[H\e[J'
	while read idx; do
		let 'count+=1'
		[[ "$idx" == 'done' ]] && prs '\n%b\e[0J' $clr_default && break
		[[ $count -lt $start_menu_idx ]] && continue
		[[ $count == $select_menu_idx ]] && clr_line=$clr_select || clr_line=$clr_default
		prs '\n%b>%b %s\e[K' $clr_select $clr_line $(echo "${stdin[$idx]}" | cut -c 1-$item_width)
		[[ $(($count-$start_menu_idx+2)) == $(($max_height)) ]] && break
	done < $filename
	print_search
}

print_search () {
	cursor_hide
	search_width=$(($(tput cols)-${#prompt}))
	prs '%b\e[H\r%s\e[K' $clr_default $(echo "$prompt$searchtext" | cut -c 1-$search_width)
	cursor_show
}

deselect_item () {
	get_menu_index
	get_select_index
	get_start_index
	if [[ $select_menu_idx -ge 0 ]] && [[ $select_idx -ge 0 ]]; then
		cursor_hide
		# move cursor to selected item
		prs '\e[%iB' $(($select_menu_idx-$start_menu_idx+1))
		# reprint selected item with default color
		prs '\r%b>%b %s\e[0K' $clr_select $clr_default $(echo "${stdin[$select_idx]}" | cut -c 1-$item_width)
	fi
	# return cursor to search text
	print_search
}

reselect_item () {
	get_menu_index
	get_select_index
	get_start_index
	if [[ $select_menu_idx -ge 0 ]] && [[ $select_idx -ge 0 ]]; then
		cursor_hide
		# move cursor to selected item
		prs '\e[%iB' $(($select_menu_idx-$start_menu_idx+1))
		# reprint selected item with default color
		prs '\r%b> %s\e[0K' $clr_select $(echo "${stdin[$select_idx]}" | cut -c 1-$item_width)
	fi
	# return cursor to search text
	print_search
}

get_indexes () {
	if $need_index_refresh; then
		filename="$index_file$index_cache_num"
		indexes=()
		while read idx; do
			[[ "$idx" == 'done' ]] && break
			indexes+=($idx)
		done < $filename
		need_index_refresh=false
	fi
}

#TODO: the get/save functions can be consolidated to one function that takes the variable + filename as input
get_menu_index () {
	read select_menu_idx < $menu_file
}

save_menu_index () {
	rm $menu_file 2>/dev/null
	echo "$select_menu_idx" > $menu_file
}

get_start_index () {
	read start_menu_idx < $start_file
}

save_start_index () {
	rm $start_file 2>/dev/null
	echo "$start_menu_idx" > $start_file
}

get_select_index () {
	read select_idx < $select_file
}

save_select_index () {
	rm $select_file 2>/dev/null
	echo "$select_idx" > $select_file
}

update_filter () {
	let 'index_cache_num+=1'
	kill $filter_proc 2>/dev/null
	filter_search &
	filter_proc=$!
}

revert_filter () {
	let 'index_cache_num-=1'
	kill $filter_proc 2>/dev/null
	filter_prev_search &
	filter_proc=$!
}

reprint () {
	kill $print_proc 2>/dev/null
	queue_print &
	print_proc=$!
}

queue_print () {
	# wait for filtering to finish before printing
	while [[ ! -z $filter_proc ]] && $(kill -0 $filter_proc 2>/dev/null); do
		sleep .01
	done
	print_menu
}

# Main():
save_select_index
save_menu_index
save_start_index
reprint
loop=true
while $loop; do
	# wait for user input	#print_search
	read -s -N 1 </dev/tty
	
	case $REPLY in
	# ESC
	($'\x1b')
		# Grab any additional input for escape characters
		read -s -t.0001 </dev/tty
		case $REPLY in
		# Up arrow
		('[A'|'OA')
			if ! $(kill -0 $filter_proc 2>/dev/null) &&
				! $(kill -0 $print_proc 2>/dev/null); then
				get_indexes
				get_menu_index
				get_start_index
				if [[ $select_menu_idx -gt 0 ]]; then
					deselect_item
					let 'select_menu_idx-=1'
					save_menu_index
					select_idx=${indexes[$select_menu_idx]}
					save_select_index
					max_height=$(($(tput lines)-3))
					if [[ $select_menu_idx -lt $start_menu_idx ]]; then
						let 'start_menu_idx-=1'
						save_start_index
						reprint
					else
						reselect_item
					fi
				fi
			fi
		;;
		# Down arrow
		('[B'|'OB')
			if ! $(kill -0 $filter_proc 2>/dev/null) &&
				! $(kill -0 $print_proc 2>/dev/null); then
				get_indexes
				get_menu_index
				get_start_index
				if [[ $select_menu_idx -lt $((${#indexes[@]}-1)) ]]; then
					deselect_item
					let 'select_menu_idx+=1'
					save_menu_index
					select_idx=${indexes[$select_menu_idx]}
					save_select_index
					max_height=$(($(tput lines)-3))
					if [[ $select_menu_idx -gt $(($start_menu_idx+$max_height)) ]]; then
						let 'start_menu_idx+=1'
						save_start_index
						reprint
					else
						reselect_item
					fi
				fi
			fi
		;;
		# ESC
		('')
			loop=false
			select_item=''
		;;
		esac
	;;
	# Backspace
	($'\x7f')
		if [[ ! -z $searchtext ]]; then 
			searchtext=${searchtext::-1}
			need_index_refresh=true
			deselect_item
			revert_filter
			reprint
		fi
	;;
	# Enter
	($'\n')
		loop=false
		wait $filter_proc
		get_select_index
		[[ $select_idx -ge 0 ]] && select_item="${stdin[$select_idx]}"
	;;
	(*)
		searchtext=$searchtext$REPLY
		need_index_refresh=true
		deselect_item
		update_filter
		reprint
	;;
	esac
	
done

kill $filter_proc 2>/dev/null
kill $print_proc 2>/dev/null

# start background shell to clear old cache files
[[ -e $cache_dir ]] && mv $cache_dir $cache_to_delete_dir$cache_ID
rm -rf $cache_to_delete_dir* &

#TODO: catch CTRL+C (and other kill commands) and make sure my background shells are stopped

# restore previous contents of terminal if possible, otherwise clear screen
tput rmcup || prs '\e[H\e[J'
# print the results to stdout
echo "$select_item"
