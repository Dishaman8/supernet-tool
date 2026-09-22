#!/usr/bin/env bash
# supernetv6-tool.sh | Supernet Tool IPv6 - interactive IPv6 subnet calculator
# Python 3's standard-library ipaddress module provides precise 128-bit IPv6 math.
# Author: Dishaman8 | Date: 22-09-2026
set -u
set -o pipefail

RESET=$'\033[0m'; BOLD=$'\033[1m'; CYAN=$'\033[36m'; BLUE=$'\033[34m'
GREEN=$'\033[32m'; YELLOW=$'\033[33m'; MAGENTA=$'\033[35m'

clear_screen() { printf '\033[2J\033[H'; }

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
  center_text 'Supernet Tool IPv6' "${BOLD}${MAGENTA}S${CYAN}u${BLUE}p${GREEN}e${YELLOW}r${MAGENTA}n${CYAN}e${BLUE}t ${GREEN}T${YELLOW}o${MAGENTA}o${CYAN}l ${BOLD}${BLUE}IPv6${RESET}"
  center_text 'IPv6 subnetting made simple' "${BOLD}${BLUE}IPv6 subnetting made simple${RESET}"
  echo
  center_text 'Plan equal-size or branch-specific IPv6 subnet ranges.' 'Plan equal-size or branch-specific IPv6 subnet ranges.'
  center_text 'Enter an IPv6 address and prefix, then receive precise address ranges.' 'Enter an IPv6 address and prefix, then receive precise address ranges.'
  center_text 'Choose a calculation below to start planning with confidence.' 'Choose a calculation below to start planning with confidence.'
  echo
}

read_positive() {
  local answer
  while :; do
    read -r -p "$1" answer
    [[ $answer =~ ^[1-9][0-9]*$ ]] && { REPLY=$answer; return; }
    echo 'Please enter a positive whole number.'
  done
}

prompt_network() {
  local ip cidr normalized
  while :; do
    read -r -p 'Enter IPv6 address: ' ip
    read -r -p 'Enter CIDR prefix (0-128): ' cidr
    [[ $cidr =~ ^[0-9]+$ ]] || { echo 'CIDR must be a number from 0 to 128.'; continue; }
    normalized=$(python3 -c 'import ipaddress, sys
try:
    prefix = int(sys.argv[2])
    if not 0 <= prefix <= 128: raise ValueError
    print(ipaddress.ip_network((sys.argv[1], prefix), strict=False))
except ValueError:
    sys.exit(1)' "$ip" "$cidr") || { echo 'Invalid IPv6 address or CIDR. Try again.'; continue; }
    INPUT_IP=$ip
    BASE_NETWORK=${normalized%/*}
    BASE_CIDR=${normalized#*/}
    [[ "$ip/$cidr" == "$normalized" ]] || echo "Note: $ip/$cidr belongs to $normalized; that network will be used."
    return
  done
}

render_equal() {
  python3 -c '
import ipaddress, sys
network = ipaddress.ip_network(sys.argv[1])
mode, requested = sys.argv[2], int(sys.argv[3])
if mode == "subnets":
    added_bits = (requested - 1).bit_length()
    prefix = network.prefixlen + added_bits
    if prefix > 128: raise ValueError("That many subnets cannot fit in the supplied network.")
    count = requested
    details = f"requested subnets: {requested} | subnet size: /{prefix}"
    possible = 1 << added_bits
    note = f"Note: the prefix creates {possible} equal subnets; showing the {requested} requested." if possible > requested else ""
else:
    host_bits = (requested - 1).bit_length()
    prefix = 128 - host_bits
    if prefix < network.prefixlen: raise ValueError("The requested address capacity is larger than the supplied network.")
    count = 1 << (prefix - network.prefixlen)
    details = f"addresses/subnet: {requested} | subnet size: /{prefix} | subnets: {count}"
    note = ""
if count > 10000:
    raise ValueError(f"This request would print {count:,} rows. Choose a larger subnet size or request a specific number of subnets.")
block = 1 << (128 - prefix)
start = int(network.network_address)
print(f"Parameters: input {sys.argv[1]} | {details}")
if note: print(note)
print("IPv6 has no broadcast address; the final column shows the subnet prefix.")
print()
print("{:<5} {:<40} {:<40} {:<40} {:<8}".format("No", "Network ID", "First Usable IP", "Last IPv6 Address", "Prefix"))
print("{:<5} {:<40} {:<40} {:<40} {:<8}".format("-----", "---------------------------------------", "---------------------------------------", "---------------------------------------", "--------"))
for i in range(count):
    address = start + i * block
    first = address if prefix == 128 else address + 1
    last = address + block - 1
    network_label = str(ipaddress.IPv6Address(address)) + "/" + str(prefix)
    print(f"{i + 1:<5} {network_label:<40} {str(ipaddress.IPv6Address(first)):<40} {str(ipaddress.IPv6Address(last)):<40} /{prefix:<7}")
' "$BASE_NETWORK/$BASE_CIDR" "$1" "$2"
}

render_custom() {
  python3 -c '
import ipaddress, sys
network = ipaddress.ip_network(sys.argv[1])
hosts = [int(value) for value in sys.argv[2:]]
entries = []
for number, required in enumerate(hosts, 1):
    prefix = 128 - (required - 1).bit_length()
    if prefix < network.prefixlen:
        raise ValueError(f"Branch {number} cannot fit inside the supplied network.")
    entries.append((number, required, prefix, 1 << (128 - prefix)))
if sum(entry[3] for entry in entries) > network.num_addresses:
    raise ValueError("The requested branch subnets exceed the supplied network capacity.")
cursor, end = int(network.network_address), int(network.broadcast_address) + 1
assigned = {}
for number, required, prefix, block in sorted(entries, key=lambda entry: (-entry[3], entry[0])):
    cursor = ((cursor + block - 1) // block) * block
    if cursor + block > end:
        raise ValueError("The requested branch layout cannot be aligned within this network.")
    assigned[number] = (cursor, prefix)
    cursor += block
print(f"Parameters: input {sys.argv[1]} | branches: {len(entries)} | allocation: VLSM (largest requirements assigned first)")
for number, required, prefix, block in entries:
    print(f"  Branch {number}: {required} IPv6 addresses requested (/{prefix})")
print("IPv6 has no broadcast address; the final column shows the subnet prefix.")
print()
print("{:<5} {:<40} {:<40} {:<40} {:<8}".format("No", "Network ID", "First Usable IP", "Last IPv6 Address", "Prefix"))
print("{:<5} {:<40} {:<40} {:<40} {:<8}".format("-----", "---------------------------------------", "---------------------------------------", "---------------------------------------", "--------"))
for number, required, prefix, block in entries:
    address, prefix = assigned[number]
    size = 1 << (128 - prefix)
    first = address if prefix == 128 else address + 1
    last = address + size - 1
    network_label = str(ipaddress.IPv6Address(address)) + "/" + str(prefix)
    print(f"{number:<5} {network_label:<40} {str(ipaddress.IPv6Address(first)):<40} {str(ipaddress.IPv6Address(last)):<40} /{prefix:<7}")
' "$BASE_NETWORK/$BASE_CIDR" "${BRANCH_HOSTS[@]}"
}

equal_subnets() {
  local method quantity
  echo >&2
  echo 'Equal subnetting: divide an IPv6 network into equally sized subnets.' >&2
  prompt_network
  echo 'Choose how to size the subnets:' >&2
  echo '  1) Number of subnets' >&2
  echo '  2) Required IPv6 addresses per subnet' >&2
  while :; do
    read -r -p 'Selection [1-2]: ' method
    [[ $method == 1 || $method == 2 ]] && break
    echo 'Enter 1 or 2.'
  done
  if [[ $method == 1 ]]; then
    read_positive 'How many subnets do you need? '; quantity=$REPLY
    render_equal subnets "$quantity"
  else
    read_positive 'How many IPv6 addresses are needed in each subnet? '; quantity=$REPLY
    render_equal hosts "$quantity"
  fi
}

custom_subnets() {
  local branches i
  local -a BRANCH_HOSTS
  echo >&2
  echo 'Custom subnetting: assign a different IPv6 address capacity to each branch.' >&2
  prompt_network
  read_positive 'How many branches do you have? '; branches=$REPLY
  (( branches <= 10000 )) || { echo 'Please use 10,000 branches or fewer.'; return 1; }
  for ((i=1; i<=branches; i++)); do
    read_positive "IPv6 addresses required for branch $i: "
    BRANCH_HOSTS[i]=$REPLY
  done
  render_custom
}

save_result() {
  local result_file=$1 destination
  while :; do
    read -r -p 'Save as (press Enter for supernetv6-result.txt): ' destination
    destination=${destination:-supernetv6-result.txt}
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
      [Nn]) echo 'Thank you for using Supernet Tool IPv6.'; exit 0 ;;
      *) echo 'Please enter P, Y, or N.' ;;
    esac
  done
}

run_calculation() {
  local mode=$1 result_file status
  result_file=$(mktemp /tmp/supernetv6-tool-result.XXXXXX)
  if [[ $mode == equal ]]; then equal_subnets | tee "$result_file"; else custom_subnets | tee "$result_file"; fi
  status=$?
  (( status == 0 )) && after_result "$result_file"
  rm -f -- "$result_file"
}

main() {
  local choice
  while :; do
    welcome_screen
    printf '  %b1)%b Divide an IPv6 network equally\n' "$GREEN$BOLD" "$RESET"
    printf '  %b2)%b Custom IPv6 subnetting for branches\n' "$GREEN$BOLD" "$RESET"
    printf '  %b3)%b Exit\n' "$GREEN$BOLD" "$RESET"
    read -r -p 'Choose an option [1-3]: ' choice
    case $choice in
      1) run_calculation equal ;;
      2) run_calculation custom ;;
      3) echo 'Thank you for using Supernet Tool IPv6.'; exit 0 ;;
      *) echo 'Invalid choice. Please enter 1, 2, or 3.' ;;
    esac
  done
}

main "$@"
