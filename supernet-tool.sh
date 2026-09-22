#!/usr/bin/env bash
# supernet-tool.sh | Supernet Tool - an interactive IPv4 subnet calculator
# Author: Dishaman8 | Date: 22-09-2026
set -u
set -o pipefail

RESET=$'\033[0m'
BOLD=$'\033[1m'
CYAN=$'\033[36m'
BLUE=$'\033[34m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
MAGENTA=$'\033[35m'

ip_to_int() {
  local ip=$1 a b c d
  IFS=. read -r a b c d <<< "$ip"
  [[ ${a:-} =~ ^[0-9]+$ && ${b:-} =~ ^[0-9]+$ && ${c:-} =~ ^[0-9]+$ && ${d:-} =~ ^[0-9]+$ ]] || return 1
  (( 10#$a <= 255 && 10#$b <= 255 && 10#$c <= 255 && 10#$d <= 255 )) || return 1
  printf '%u\n' "$(( (10#$a << 24) + (10#$b << 16) + (10#$c << 8) + 10#$d ))"
}

int_to_ip() {
  local n=$1
  printf '%d.%d.%d.%d' "$(( (n >> 24) & 255 ))" "$(( (n >> 16) & 255 ))" \
    "$(( (n >> 8) & 255 ))" "$(( n & 255 ))"
}

mask_for_prefix() {
  local prefix=$1
  if (( prefix == 0 )); then printf '0\n'; else printf '%u\n' "$(( (0xFFFFFFFF << (32-prefix)) & 0xFFFFFFFF ))"; fi
}

block_for_prefix() {
  local prefix=$1
  printf '%u\n' "$(( 1 << (32-prefix) ))"
}

prefix_for_hosts() {
  # Standard IPv4 subnets reserve a network and broadcast address.
  local hosts=$1 bits=2
  while (( (1 << bits) - 2 < hosts && bits < 32 )); do ((bits++)); done
  (( bits <= 32 )) || return 1
  printf '%d\n' "$((32-bits))"
}

prompt_network() {
  local ip cidr value mask
  while :; do
    read -r -p 'Enter IPv4 address: ' ip
    value=$(ip_to_int "$ip") || { echo 'Invalid IPv4 address. Try again.'; continue; }
    read -r -p 'Enter CIDR prefix (0-30): ' cidr
    [[ $cidr =~ ^[0-9]+$ ]] && (( 10#$cidr >= 0 && 10#$cidr <= 30 )) || { echo 'CIDR must be a number from 0 to 30.'; continue; }
    cidr=$((10#$cidr))
    mask=$(mask_for_prefix "$cidr")
    BASE_NETWORK=$(( value & mask ))
    BASE_CIDR=$cidr
    INPUT_IP=$ip
    if (( value != BASE_NETWORK )); then
      echo "Note: $ip/$cidr belongs to $(int_to_ip "$BASE_NETWORK")/$cidr; that network will be used."
    fi
    return
  done
}

print_header() {
  printf '\n%-5s %-18s %-18s %-18s %-18s\n' 'No' 'Network ID' 'First Valid IP' 'Last Valid IP' 'Broadcast IP'
  printf '%-5s %-18s %-18s %-18s %-18s\n' '-----' '-----------------' '-----------------' '-----------------' '-----------------'
}

print_subnet_row() {
  local number=$1 network=$2 prefix=$3 block broadcast first last
  block=$(block_for_prefix "$prefix")
  broadcast=$((network + block - 1))
  first=$((network + 1))
  last=$((broadcast - 1))
  printf '%-5s %-18s %-18s %-18s %-18s\n' "$number" \
    "$(int_to_ip "$network")/$prefix" "$(int_to_ip "$first")" \
    "$(int_to_ip "$last")" "$(int_to_ip "$broadcast")"
}

read_positive() {
  local answer
  while :; do
    read -r -p "$1" answer
    [[ $answer =~ ^[1-9][0-9]*$ ]] && { REPLY=$((10#$answer)); return; }
    echo 'Please enter a positive whole number.'
  done
}

equal_subnets() {
  local method quantity host_bits new_prefix available i base_block
  echo >&2
  echo 'Equal subnetting: divide a network into equally sized subnets.' >&2
  prompt_network
  echo 'Choose how to size the subnets:' >&2
  echo '  1) Number of subnets' >&2
  echo '  2) Required usable hosts per subnet' >&2
  while :; do
    read -r -p 'Selection [1-2]: ' method
    [[ $method == 1 || $method == 2 ]] && break
    echo 'Enter 1 or 2.'
  done

  if [[ $method == 1 ]]; then
    read_positive 'How many subnets do you need? '
    quantity=$REPLY
    host_bits=0
    while (( (1 << host_bits) < quantity )); do ((host_bits++)); done
    new_prefix=$((BASE_CIDR + host_bits))
    (( new_prefix <= 30 )) || { echo 'That many standard subnets cannot fit in the supplied network.'; return 1; }
    available=$((1 << host_bits))
    echo
    echo "Parameters: input $INPUT_IP/$BASE_CIDR | requested subnets: $quantity | subnet size: /$new_prefix"
    (( available > quantity )) && echo "Note: the prefix creates $available equal subnets; showing the $quantity requested."
  else
    read_positive 'How many usable hosts are needed in each subnet? '
    quantity=$REPLY
    new_prefix=$(prefix_for_hosts "$quantity") || { echo 'Host requirement is too large.'; return 1; }
    (( new_prefix >= BASE_CIDR )) || { echo 'The requested host capacity is larger than the supplied network.'; return 1; }
    host_bits=$((new_prefix - BASE_CIDR))
    available=$((1 << host_bits))
    quantity=$available
    echo
    echo "Parameters: input $INPUT_IP/$BASE_CIDR | usable hosts/subnet: $REPLY | subnet size: /$new_prefix | subnets: $available"
  fi

  base_block=$(block_for_prefix "$new_prefix")
  print_header
  for ((i=0; i<quantity; i++)); do print_subnet_row "$((i+1))" "$((BASE_NETWORK + i * base_block))" "$new_prefix"; done
}

custom_subnets() {
  local branches i hosts prefix block total=0 cursor base_end order line branch
  local -a branch_hosts branch_prefix branch_block
  echo >&2
  echo 'Custom subnetting: assign a different usable-host capacity to each branch.' >&2
  prompt_network
  read_positive 'How many branches do you have? '
  branches=$REPLY
  for ((i=1; i<=branches; i++)); do
    read_positive "Usable hosts required for branch $i: "
    branch_hosts[i]=$REPLY
    branch_prefix[i]=$(prefix_for_hosts "${branch_hosts[i]}") || { echo "Branch $i has an invalid host requirement."; return 1; }
    (( branch_prefix[i] >= BASE_CIDR )) || { echo "Branch $i cannot fit inside the supplied network."; return 1; }
    branch_block[i]=$(block_for_prefix "${branch_prefix[i]}")
    total=$((total + branch_block[i]))
  done
  base_end=$((BASE_NETWORK + $(block_for_prefix "$BASE_CIDR")))
  (( total <= base_end - BASE_NETWORK )) || { echo 'The requested branch subnets exceed the supplied network capacity.'; return 1; }

  # VLSM allocation starts with the largest blocks so alignment remains valid.
  order=$(for ((i=1; i<=branches; i++)); do printf '%s %s\n' "${branch_block[i]}" "$i"; done | sort -rn)
  cursor=$BASE_NETWORK
  declare -A assigned_network
  while read -r block branch; do
    (( cursor % block == 0 )) || cursor=$(( (cursor / block + 1) * block ))
    (( cursor + block <= base_end )) || { echo 'The requested branch layout cannot be aligned within this network.'; return 1; }
    assigned_network[$branch]=$cursor
    cursor=$((cursor + block))
  done <<< "$order"

  echo
  echo "Parameters: input $INPUT_IP/$BASE_CIDR | branches: $branches | allocation: VLSM (largest requirements assigned first)"
  for ((i=1; i<=branches; i++)); do
    echo "  Branch $i: ${branch_hosts[i]} usable hosts requested (/${branch_prefix[i]})"
  done
  print_header
  for ((i=1; i<=branches; i++)); do
    print_subnet_row "$i" "${assigned_network[$i]}" "${branch_prefix[i]}"
  done
}

clear_screen() {
  # ANSI escape codes work even when the `clear` command is unavailable.
  printf '\033[2J\033[H'
}

center_text() {
  local plain=$1 styled=$2 columns padding
  columns=$(tput cols 2>/dev/null || printf '80')
  (( columns < ${#plain} )) && columns=${#plain}
  padding=$(( (columns - ${#plain}) / 2 ))
  printf '%*s%b\n' "$padding" '' "$styled"
}

welcome_screen() {
  clear_screen
  echo
  center_text 'Welcome' "${BOLD}${CYAN}Welcome${RESET}"
  center_text 'Supernet Tool' "${BOLD}${MAGENTA}S${CYAN}u${BLUE}p${GREEN}e${YELLOW}r${MAGENTA}n${CYAN}e${BLUE}t ${GREEN}T${YELLOW}o${MAGENTA}o${CYAN}l${RESET}"
  center_text 'IPv4 subnetting made simple' "${BOLD}${BLUE}IPv4 subnetting made simple${RESET}"
  echo
  center_text 'Plan equal-size or branch-specific IPv4 subnet ranges.' 'Plan equal-size or branch-specific IPv4 subnet ranges.'
  center_text 'Enter a network and CIDR, then receive valid host and broadcast addresses.' 'Enter a network and CIDR, then receive valid host and broadcast addresses.'
  center_text 'Choose a calculation below to start planning with confidence.' 'Choose a calculation below to start planning with confidence.'
  echo
}

save_result() {
  local result_file=$1 destination
  while :; do
    read -r -p 'Save as (press Enter for supernet-result.txt): ' destination
    destination=${destination:-supernet-result.txt}
    [[ $destination == *.txt ]] || destination+='.txt'
    if [[ -e $destination ]]; then
      read -r -p "'$destination' exists. Overwrite it? [y/N]: " REPLY
      [[ $REPLY =~ ^[Yy]$ ]] || continue
    fi
    cp -- "$result_file" "$destination" && { echo "Result saved to: $destination"; return; }
    echo 'Could not save the file. Please choose another valid path.'
  done
}

after_result() {
  local result_file=$1 action
  while :; do
    echo
    read -r -p 'Press P to save as a TXT file, Y to calculate again, or N to exit: ' action
    case $action in
      [Pp]) save_result "$result_file" ;;
      [Yy]) clear_screen; return ;;
      [Nn]) echo 'Thank you for using Supernet Tool.'; exit 0 ;;
      *) echo 'Please enter P, Y, or N.' ;;
    esac
  done
}

run_calculation() {
  local mode=$1 result_file
  result_file=$(mktemp /tmp/supernet-tool-result.XXXXXX)
  if [[ $mode == equal ]]; then
    equal_subnets | tee "$result_file"
  else
    custom_subnets | tee "$result_file"
  fi
  if (( $? == 0 )); then after_result "$result_file"; fi
  rm -f -- "$result_file"
}

main() {
  local choice
  while :; do
    welcome_screen
    printf '  %b1)%b Divide a network equally\n' "$GREEN$BOLD" "$RESET"
    printf '  %b2)%b Custom subnetting for branches\n' "$GREEN$BOLD" "$RESET"
    printf '  %b3)%b Exit\n' "$GREEN$BOLD" "$RESET"
    read -r -p 'Choose an option [1-3]: ' choice
    case $choice in
      1) run_calculation equal ;;
      2) run_calculation custom ;;
      3) echo 'Thank you for using Supernet Tool.'; exit 0 ;;
      *) echo 'Invalid choice. Please enter 1, 2, or 3.' ;;
    esac
  done
}

main "$@"
