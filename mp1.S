# I callee-save all the Registers I use in the functions
# v2.3
.data					# section declaration

        # Useful offset constants for accessing members of a
        # struct mp1_blink_struct structure
        LOCATION   = 0
        ON_CHAR    = 2
        OFF_CHAR   = 3
        ON_LENGTH  = 4
        OFF_LENGTH = 6
        COUNTDOWN  = 8
        STATUS     = 10
        NEXT       = 12

        STRUCT_SIZE = 16

        # self-declared members

        LAST_LOCATION = 1999
        # 25 * 80 - 1 = 1999

# Pointer to head of list (initialized to NULL)
mp1_list_head:
        .long   0

.text					# section declaration

# Export the function symbol names

.global mp1_rtc_tasklet
.global mp1_ioctl

# void mp1_poke(void);
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX
mp1_poke:

	movl    vmem_base_addr(,1),%edx
	movb    %cl,(%edx,%eax,1)
	ret

# This function does not need any arguments
mp1_rtc_tasklet:
  # store and update ebp, push ebx, ecx (callee-save)
  pushl  %ebp
  movl  %esp, %ebp
  pushl  %ebx
  pushl  %ecx
  pushl  %esi
  pushl  %edi
  pushl  %edx

  # load mp1_list_head to ebx
  movl  mp1_list_head, %ebx
  cmpl  $0, %ebx

  je  tasklet_done

  xorl  %ecx, %ecx

  # enter the loop to check each node
tasklet_loop:
  # decrement
  movw  COUNTDOWN(%ebx), %cx
  subw  $1, %cx
  movw  %cx, COUNTDOWN(%ebx)

  cmpw  $0, %cx
  je tasklet_update
  jmp tasklet_next

tasklet_update:
# update node parameters and poke according to STATUS
  # examine STATUS
  xorl  %ecx, %ecx
  movw  STATUS(%ebx), %cx
  cmpw  $0, %cx
  je tasklet_turnon

  # STATUS currently 1, turn off

  # poke
  xorl  %ecx, %ecx
  movw  LOCATION(%ebx), %cx
  leal  (%ecx, %ecx), %eax
  movb  OFF_CHAR(%ebx), %cl
  call  mp1_poke

  # update some parameters
  movw  OFF_LENGTH(%ebx), %cx
  movw  %cx, COUNTDOWN(%ebx)
  movw  $0, STATUS(%ebx)

  jmp tasklet_next

tasklet_turnon:
  # STATUS currently 0, turn on

  # poke
  xorl  %ecx, %ecx
  movw  LOCATION(%ebx), %cx
  leal  (%ecx, %ecx), %eax
  movb  ON_CHAR(%ebx), %cl
  call  mp1_poke

  # update some parameters
  movw  ON_LENGTH(%ebx), %cx
  movw  %cx, COUNTDOWN(%ebx)
  movw  $1, STATUS(%ebx)

tasklet_next:
# done operating on the current node, move on to next
  movl  NEXT(%ebx), %ebx
  cmpl  $0, %ebx
  jne tasklet_loop

tasklet_done:
  # restore and tear down stack
  popl  %edx
  popl  %edi
  popl  %esi
  popl  %ecx
  popl  %ebx
  popl  %ebp

	ret

# This function does not modify stack but jump to other functions through jump jump_table
mp1_ioctl:
  movl  $1, %eax  # set return value to 1
  movl  8(%esp), %ebx  # load command number into ebx

  # check whether command number is valid
  cmpl  $3, %ebx
  jg invalid
  cmpl  $0, %ebx
  jl invalid

  # check jump_table to determine which function to call
  jmp *jump_table(, %ebx, 4)


  # case command number is invalid
invalid:
  movl $-1, %eax  # set the return value to -1
  ret

# add a new node to the list and poke the new node
mp1_ioctl_add:
  # store and update ebp, push ebx, esi
  pushl  %ebp
  movl  %esp, %ebp
  pushl  %ebx
  pushl  %esi
  pushl  %edi
  pushl  %ecx
  pushl  %edx

  movl  8(%ebp), %esi

# malloc a structure
  # store 1 argument
  pushl  $STRUCT_SIZE
  call  mp1_malloc
  # tear down argument
  leal  4(%esp), %esp

  movl  %eax, %ebx   # use ebx to store the pointer
  # check malloc error
  cmpl  $0, %ebx
  je  add_malloc_error

# copy from user kernel
  # check null ptr
  cmpl  $0, %esi
  je  copy_error

  # store 3 arguments
  pushl  $STRUCT_SIZE
  pushl  %esi
  pushl  %ebx
  call  mp1_copy_from_user
  # tear down arguments
  leal  12(%esp), %esp

  # copy error detection
  cmpl  $0, %eax
  jne  copy_error

  # check location
  movw  LOCATION(%ebx), %cx
  cmpw  $0, %cx
  jl copy_error
  cmpw  $LAST_LOCATION, %cx
  jg copy_error

  # adjust some parameters
  movw  ON_LENGTH(%ebx), %cx
  movw  %cx, COUNTDOWN(%ebx)
  movw  $1, STATUS(%ebx)

  # insert the structure
  movl  mp1_list_head, %ecx
  movl  %ecx, NEXT(%ebx)
  movl  %ebx, mp1_list_head

  # poke
  xorl  %ecx, %ecx
  movw  LOCATION(%ebx), %cx
  leal  (%ecx, %ecx), %eax
  movb  ON_CHAR(%ebx), %cl
  call mp1_poke

  # set return value
  movl $0, %eax
  jmp mp1_add_done

copy_error:
  # free the memory
  pushl  %ebx
  call mp1_free
  leal 4(%esp), %esp
  # set return value
add_malloc_error:
  movl  $-1, %eax

mp1_add_done:
# tear down stack and return
  popl  %edx
  popl  %ecx
  popl  %edi
  popl  %esi
  popl  %ebx
  popl  %ebp
	ret

mp1_ioctl_remove:
  # store and update ebp, push ebx, ecx, edx, esi
  pushl  %ebp
  movl  %esp, %ebp
  pushl  %ebx
  pushl  %ecx
  pushl  %edx
  pushl  %esi
  pushl  %edi

# retrieve the argument with ebx
  xorl  %ebx, %ebx
  movl  8(%ebp), %ebx

# retrieve addr of target node
  pushl  %ebx
  call  mp1_search
  leal  4(%esp), %esp  # tear down the stack

# check error of addr
  cmpl  $0, %eax
  je  remove_error

# remove the target node from list
# check if target node is mp1_list_head
  cmpl  %eax, mp1_list_head
  je remove_head

# target node not mp1_list_head
  movl  NEXT(%eax), %edx
  movl  %edx, NEXT(%ecx)
  jmp  remove_free

remove_head:
  movl  NEXT(%eax), %esi
  movl  %esi, mp1_list_head

remove_free:
# free target
  pushl  %eax
  call  mp1_free
  leal  4(%esp), %esp
  movl  $0, %eax
  jmp  remove_done

remove_error:
  movl  $-1, %eax

remove_done:
# tear down stack and return
  popl  %edi
  popl  %esi
  popl  %edx
  popl  %ecx
  popl  %ebx
  popl  %ebp

	ret

mp1_ioctl_find:
  # store and update ebp, push ebx, ecx, edx, esi
  pushl  %ebp
  movl  %esp, %ebp
  pushl  %ebx
  pushl  %ecx
  pushl  %edx
  pushl  %esi
  pushl  %edi

  # load arg to ebx and check if the addr valid
  movl  8(%ebp), %ebx
  cmpl  $0, %ebx
  je  find_error

  # load LOCATION of input to cx
  xorl  %ecx, %ecx
  movw  LOCATION(%ebx), %cx

  # check error of LOCATION
  cmpw  $0, %cx
  jl  find_error
  cmpw  $LAST_LOCATION, %cx
  jg  find_error

  # store location and call mp1_search
  # caller-save ecx
  movl  %ecx, %edi

  pushl  %ecx
  call  mp1_search
  leal  4(%esp), %esp  # tear down bookkeeping

  movl  %edi, %ecx

  # check error of addr
  cmpl  $0, %eax
  je  find_error

  # copy structure pointed by eax to user kernel
  pushl  $STRUCT_SIZE
  pushl  %eax
  pushl  %ebx
  call  mp1_copy_to_user

  # tear down bookkeeping
  leal  12(%esp), %esp

  # check error of output
  cmpl  $0, %eax
  jne  find_error
  movl  $0, %eax
  jmp  find_done

find_error:
# some error occurs, set eax to -1 and return
  movl  $-1, %eax
  jmp  find_done

find_done:
  # tear down stack and return
  popl  %edi
  popl  %esi
  popl  %edx
  popl  %ecx
  popl  %ebx
  popl  %ebp

	ret

mp1_ioctl_sync:
# push and update ebp, push ebx, ecx, esi, edi, edx
  pushl  %ebp
  movl  %esp, %ebp
  pushl  %ebx
  pushl  %ecx
  pushl  %esi
  pushl  %edi
  pushl  %edx

# fetch the first LOCATION into bx, the second into cx
  xorl  %ebx, %ebx
  xorl  %ecx, %ecx
  movw  8(%ebp), %cx
  movw  10(%ebp), %bx

  # check error of the LOCATIONs
  cmpw  $0, %cx
  jl  sync_error
  cmpw  $LAST_LOCATION, %cx
  jg  sync_error
  cmpw  $0, %bx
  jl  sync_error
  cmpw  $LAST_LOCATION, %bx
  jg  sync_error

# get the addr correspoding to the two LOCATIONs
  xorl  %esi, %esi  # stores the first addr
  xorl  %edi, %edi  # stores the second addr

  # caller-save ecx
  pushl  %ecx

  pushl  %ebx
  call  mp1_search
  leal  4(%esp), %esp  # tear down the stack
  popl  %ecx           # retrieve ecx
  movl  %eax, %esi
  cmpl  $0, %esi
  je  sync_error

  # caller-save ecx
  pushl  %ecx

  pushl  %ecx
  call  mp1_search
  leal  4(%esp), %esp  # tear dow the stack
  popl  %ecx           # retrieve ecx
  movl  %eax, %edi
  cmpl  $0, %edi
  je  sync_error

# do the copy
  xorl  %edx, %edx
  movw  ON_LENGTH(%esi), %dx
  movw  %dx, ON_LENGTH(%edi)

  movw  OFF_LENGTH(%esi), %dx
  movw  %dx, OFF_LENGTH(%edi)

  movw  COUNTDOWN(%esi), %dx
  movw  %dx, COUNTDOWN(%edi)

  movw  STATUS(%esi), %dx
  movw  %dx, STATUS(%edi)

# poke the second LOCATION
  cmpw  $0, %dx
  je  sync_off

# STATUS is 1
  movb  ON_CHAR(%edi), %cl
  xorl  %edx, %edx
  movw  LOCATION(%edi), %dx
  leal  (%edx, %edx), %eax
  jmp  sync_poke

sync_off:
# STATUS is 0
  movb  OFF_CHAR(%edi), %cl
  xorl  %edx, %edx
  movw  LOCATION(%edi), %dx
  leal  (%edx, %edx), %eax

sync_poke:
  call mp1_poke

# set return value
  movl  $0, %eax
  jmp sync_done

sync_error:
# return value to -1
  movl  $-1, %eax

sync_done:
# tear down the stack
  popl  %edx
  popl  %edi
  popl  %esi
  popl  %ecx
  popl  %ebx
  popl  %ebp

	ret

mp1_search:
# a self implemented helper function, which takes in a LOCATION(extended to 4 bytes), and returns addr
# correspoding to that LOCATION, if fails to find, return 0 instead
# (the function will also store previous node to ecx upon success, ecx need caller save)

# push and update ebp, push ebx, esi, edx
  pushl  %ebp
  movl  %esp, %ebp
  pushl  %ebx
  pushl  %esi
  pushl  %edx
  pushl  %edi


# load input LOCATION into bx
  xorl  %ebx, %ebx
  movl  8(%ebp), %ebx

# check error
  cmpw  $0, %bx
  jl  search_error
  cmpw  $LAST_LOCATION, %bx
  jg  search_error

# initialize esi and ecx to mp1_list_head and start traversing
  xorl  %esi, %esi
  movl  mp1_list_head, %esi

  #check error
  cmpl  $0, %esi
  je  search_error

  xorl  %ecx, %ecx
  movl  mp1_list_head, %ecx

search_loop:
# traverse and serach for the matching node
  xorl  %edx, %edx
  movw  LOCATION(%esi), %dx
  cmpw  %dx, %bx
  jne  search_next

# the correct node found, set addr to return value
  movl  %esi, %eax
  jmp  search_done

search_next:
# current node is not correct, update ecx, go to the next node, check whether reach the end
  movl  %esi, %ecx
  movl  NEXT(%esi), %esi
  cmpl  $0, %esi
  je  search_error
  jmp  search_loop

search_error:
# node not found, set return value to 0
  movl  $0, %eax

search_done:
# tear down the stack and return

  popl  %edi
  popl  %edx
  popl  %esi
  popl  %ebx
  popl  %ebp

  ret

jump_table:
.long mp1_ioctl_add, mp1_ioctl_remove, mp1_ioctl_find, mp1_ioctl_sync


.end
