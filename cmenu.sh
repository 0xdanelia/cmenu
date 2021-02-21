#!/bin/bash

prs () { printf $@ > /dev/tty ; }
cursor_hide () { prs '%b' '\e[?25l'; }
cursor_show () { prs '%b' '\e[?25h'; }

stdin=()    # strings of input text
indexes=()  # indexes of menu items
# read piped input
if test ! -t 0; then
	count=0
	while read -rs inline; do
		stdin+=("$inline")
		indexes+=($count)
		let 'count+=1'
	done
fi

original_indexes=( ${indexes[@]} )

prs '\e[s'     # save cursor
prs '\e[?47h'  # save screen
prs '\e[H'     # move cursor to top of screen

IFS=''
searchtext=''  # user-typed filter
prompt=':'

select_idx=0
select_menu_idx=0
select_item=''

index_file='.cmenu_indexes'
select_file='.cmenu_select'

clr_select='\e[44m\e[37m'
clr_default='\e[40m\e[37m'

filter_proc=''
print_proc=''

filter_search () {
	prev_idx=-1
	count=-1

	[[ -e $index_file ]] && rm $index_file
	for idx in ${indexes[@]}; do
		if [[ $(echo ${stdin[$idx]} | grep "$searchtext") ]]; then
			let 'count+=1'
			# keep track of the item before the selected item
			[[ $idx == $select_idx ]] && select_menu_idx=$count
			 echo $idx >> $index_file
			 prev_idx=$idx
		else
			# if filter removes selected item from list, select the next available item
			[[ $idx == $select_idx ]] && let 'select_idx+=1'
		fi
	done
	echo 'done' >> $index_file

	# if filter shrinks list past selected item, select the last item
	[[ $select_idx -gt $prev_idx ]] && select_idx=$prev_idx && select_menu_idx=$count

	save_menu_index
	
	print_menu
}

print_menu () {
	get_menu_index
	count=-1
	item_width=$(($(tput cols)-2))
	max_height=$(($(tput lines)-1))
	
	cursor_hide
	prs '\e[H'
	while read idx; do
		let 'count+=1'
		[[ "$idx" == 'done' ]] && break
		[[ $count == $select_menu_idx ]] && clr_line=$clr_select || clr_line=$clr_default
		prs '\n%b>%b %s\e[K' $clr_select $clr_line $(echo "${stdin[$idx]}" | cut -c 1-$item_width)
		[[ $(($count+2)) == $max_height ]] && break
	done < $index_file
	prs '\n%b\e[0J\e[H' $clr_default
	print_search
	cursor_show
}

print_search () {
	search_width=$(($(tput cols)-${#prompt}))
	prs '\e[H\r%s\e[K' $(echo "$prompt$searchtext" | cut -c 1-$search_width)
}

print_selected () {
	print_menu
}

get_indexes () {
	indexes=()
	while read idx; do
		[[ "$idx" == 'done' ]] && break
		indexes+=($idx)
	done < $index_file
}

get_menu_index () {
	read select_menu_idx < $select_file
}

save_menu_index () {
	[[ -e $select_file ]] && rm $select_file
	echo "$select_menu_idx" > $select_file
}

update_filter () {
	kill $filter_proc 2>/dev/null
	filter_search &
	filter_proc=$!
}

# Main():
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
			wait $filter_proc
			get_indexes
			get_menu_index
			if [[ $select_menu_idx -gt 0 ]]; then
				let 'select_menu_idx-=1'
				save_menu_index
				select_idx=${indexes[$select_menu_idx]}
				print_selected
			fi
		;;
		# Down arrow
		('[B'|'OB')
			wait $filter_proc
			get_indexes
			get_menu_index
			if [[ $select_menu_idx -lt $((${#indexes[@]}-1)) ]]; then
				let 'select_menu_idx+=1'
				save_menu_index
				select_idx=${indexes[$select_menu_idx]}
				print_selected
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
			wait $filter_proc
			get_indexes
			get_menu_index
			[[ ! -z $indexes ]] && select_menu_idx=${indexes[$select_menu_idx]} || select_menu_idx=0
			select_idx=$select_menu_idx
			save_menu_index
			indexes=( ${original_indexes[@]} )
			update_filter
		fi
	;;
	# Enter
	($'\n')
		loop=false
		wait $filter_proc
		get_indexes
		get_menu_index
		[[ ! -z $indexes ]] && select_item="${stdin[${indexes[$select_menu_idx]}]}"
	;;
	(*)
		searchtext=$searchtext$REPLY
		update_filter
	;;
	esac
	
done

kill $filter_proc 2>/dev/null

prs '\e[?47l'  # restore screen
prs '\e[u'     # restore cursor

echo "$select_item"



