#!/bin/bash

prs () { printf $@ > /dev/tty ; }
cursor_hide () { prs '%b' '\e[?25l'; }
cursor_show () { prs '%b' '\e[?25h'; }

stdin=()    # strings of input text
indexes=()  # indexes of menu items  #TODO: since indexes are read from files, do we need this variable?
# read piped input
if test ! -t 0; then
	count=0
	while read -rs inline; do
		stdin+=("$inline")
		indexes+=($count)
		let 'count+=1'
	done
fi

#TODO: read ARGS for special options
# -p  set custom prompt
# -i  use case-insensitive filtering
# -c  set highlight color (possibly?)
# -l  set max menu rows to display on screen
# -s  display menu in-line instead of clearing terminal screen first

original_indexes=( ${indexes[@]} )

#TODO: move useful cursor commands to functions or variables so I don't have to keep looking them up
prs '\e[s'     # save cursor
prs '\e[?47h'  # save screen
prs '\e[H'     # move cursor to top of screen

IFS=''
searchtext=''  # user-typed filter
prompt=':'

select_idx=0
select_menu_idx=0
select_item=''

#TODO: move these files to a .cache folder
index_cache_num=0
index_file='.cmenu_indexes'
select_file='.cmenu_select'
menu_file='.cmenu_menu'
print_file='.cmenu_print'

clr_select='\e[44m\e[37m'
clr_default='\e[40m\e[37m'

filter_proc=''
print_proc=''

filter_search () {
	get_select_index
	selected=false
	prev_idx=-1
	count=-1
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

	save_menu_index
	save_select_index
	
	reprint
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
		! $selected && select_idx=0 && select_menu_idx=0
	fi

	save_menu_index
	save_select_index
	
	reprint
}

print_menu () {
	get_menu_index
	count=-1
	item_width=$(($(tput cols)-2))
	max_height=$(($(tput lines)-1))
	filename="$index_file$index_cache_num"
	
	cursor_hide
	prs '\e[H'
	while read idx; do
		let 'count+=1'
		[[ "$idx" == 'done' ]] && break
		[[ $count == $select_menu_idx ]] && clr_line=$clr_select || clr_line=$clr_default
		prs '\n%b>%b %s\e[K' $clr_select $clr_line $(echo "${stdin[$idx]}" | cut -c 1-$item_width)
		[[ $(($count+2)) == $max_height ]] && break
	done < $filename
	prs '\n%b\e[0J\e[H' $clr_default
	print_search
	print_proc=''
	save_print_proc
}

print_search () {
	get_print_proc
	wait $print_proc 2> /dev/null
	search_width=$(($(tput cols)-${#prompt}))
	prs '\e[H\r%s\e[K' $(echo "$prompt$searchtext" | cut -c 1-$search_width)
	cursor_show
}

deselect_item () {
	if [[ $select_menu_idx -ge 0 ]]; then
		get_select_index
		get_menu_index
		cursor_hide
		# move cursor to selected item
		prs '\e[%iB' $(( $select_menu_idx + 1 ))
		# reprint selected item with default color
		prs '\r%b>%b %s\e[0K' $clr_select $clr_default $(echo "${stdin[$select_idx]}" | cut -c 1-$item_width)
		# move cursor back to top of screen
		prs '\e[H'
		# print user-typed text for searching list
		print_search
	fi
}

reselect_item () {
	if [[ $select_menu_idx -ge 0 ]]; then
		get_select_index
		get_menu_index
		cursor_hide
		# move cursor to selected item
		prs '\e[%iB' $(( $select_menu_idx + 1 ))
		# reprint selected item with default color
		prs '\r%b> %s\e[0K' $clr_select $(echo "${stdin[$select_idx]}" | cut -c 1-$item_width)
		# move cursor back to top of screen
		prs '%b\e[H' $clr_default
		# print user-typed text for searching list
		print_search
	fi
}

get_indexes () {
	filename="$index_file$index_cache_num"
	indexes=()
	while read idx; do
		[[ "$idx" == 'done' ]] && break
		indexes+=($idx)
	done < $filename
}

get_menu_index () {
	read select_menu_idx < $menu_file
}

save_menu_index () {
	rm $menu_file 2> /dev/null
	echo "$select_menu_idx" > $menu_file
}

get_select_index () {
	read select_idx < $select_file
}

save_select_index () {
	rm $select_file 2> /dev/null
	echo "$select_idx" > $select_file
}

get_print_proc () {
	read print_proc < $print_file
}

save_print_proc () {
	rm $print_file 2> /dev/null
	echo "$print_proc" > $print_file
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
	get_print_proc
	[[ ! -z $print_proc ]] && kill $print_proc 2>/dev/null
	print_menu &
	print_proc=$!
	save_print_proc
}

# Main():
save_select_index
save_menu_index
save_print_proc
filter_search
loop=true
while $loop; do
	# wait for user input	#print_search
	read -s -N 1 </dev/tty
	
	case $REPLY in
	# ESC
	($'\x1b')
		# Grab any additional input for escape characters
		read -s -t.001 </dev/tty
		case $REPLY in
		# Up arrow
		('[A'|'OA')
			if ! $(kill -0 $filter_proc 2>/dev/null); then
				get_indexes
				get_menu_index
				if [[ $select_menu_idx -gt 0 ]]; then
					get_print_proc
					wait $print_proc 2> /dev/null
					deselect_item
					let 'select_menu_idx-=1'
					save_menu_index
					select_idx=${indexes[$select_menu_idx]}
					save_select_index
					reselect_item
				fi
			fi
		;;
		# Down arrow
		('[B'|'OB')
			if ! $(kill -0 $filter_proc 2>/dev/null); then
				get_indexes
				get_menu_index
				if [[ $select_menu_idx -lt $((${#indexes[@]}-1)) ]]; then
					get_print_proc
					wait $print_proc 2> /dev/null
					deselect_item
					let 'select_menu_idx+=1'
					save_menu_index
					select_idx=${indexes[$select_menu_idx]}
					save_select_index
					reselect_item
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
			get_print_proc
			kill $print_proc 2>/dev/null
			deselect_item &
			revert_filter
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
		get_print_proc
		kill $print_proc 2>/dev/null
		deselect_item &
		update_filter
	;;
	esac
	
done

kill $filter_proc 2>/dev/null
get_print_proc
kill $print_proc 2>/dev/null

#TODO: start backgroun shell to clear cache files

#TODO: catch CTRL+C (and other kill commands) and make sure my background shells are stopped

prs '\e[?47l'  # restore screen
prs '\e[u'     # restore cursor

echo "$select_item"
