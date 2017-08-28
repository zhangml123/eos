#!/bin/ksh
# Capacity Test

if [[ $# != 3 ]] && [[ $# != 4 ]]; then
  echo This is a capacity test using eosc
  echo Usage: captest.ksh NumberOfAccounts DurationSeconds Concurrency [PathToEOSD_stdoutFile]
  echo
  echo NumberOfAccounts
  echo There only needs to be enough accounts so that the same account isn\'t used in a 3 second time period
  echo So if trasfer transaction can do 3000 per 3 seconds per eosc instance, then set this number to 4000 to be safe
  echo If this number is 0 then captest.ksh will skip creating accounts
  echo
  echo DurationSeconds
  echo How long would you like this test to run
  echo
  echo Concurrency
  echo How many concurrent eosc instances would you like running at the same time
  echo
  echo PathToEOSD_stdoutFile
  echo If this optional parameter is provided then additional chain performance output will be seen during the test
  echo
  echo example:
  echo   '#get eosd running, using a fresh chain every time'
  echo   captest.ksh 3000 12 4
  echo   captest.ksh 3000 12 4 eosd-stdout.txt
  echo
  exit
fi

GrepSearchForSuccess=\"transaction_id\"
#GrepSearchForSuccess=\"eos_balance\"

echo If this process gets stuck, press Ctrl + C as eosd may have had an issue
NumberOfAccounts=$1
[[ $1 == 0 ]] && NumberOfAccounts=$(cat accounts_1_names.txt | wc -l)
DurationSeconds=$2
Concurrency=$3
PathToEOSD_stdoutFile=none
[[ $# == 4 ]] && PathToEOSD_stdoutFile=$4

echo NumberOfAccounts = $NumberOfAccounts
echo DurationSeconds = $DurationSeconds
echo Concurrency = $Concurrency
echo PathToEOSD_stdoutFile = $PathToEOSD_stdoutFile

if [[ $# == 4 ]] && [[ ! -f "$PathToEOSD_stdoutFile" ]]; then
  echo Error: The 4th parameter "$PathToEOSD_stdoutFile" could not be found or is not a file
  exit
fi

if [[ $(pgrep eosd | wc -l) == 0 ]]; then
  echo Error: Please start eosd
  exit
fi

if [[ $(which eosc | wc -l) == 0 ]]; then
  echo Error: Cannot find eosc in \$PATH
  exit
fi

if [[ $(which eosc | wc -l) == 0 ]]; then
  echo Error: Cannot find eosc in \$PATH
  exit
fi

# kill previous captest if it is still running
if [[ $(pgrep captest.ksh | wc -l) > 1 ]]; then
  for p in $(pgrep captest.ksh)
  do
    [[ $p == $$ ]] && continue
    kill -9 $p
  done
fi
pkill -9 eosc


function NewFile
{
  rm $1 2>/dev/null
  touch $1
}

function RemoveDone
{
  for Inst in $(seq $Concurrency); do; rm accounts_${Inst}_done.txt 2>/dev/null; done;
}

function WaitDone
{
  for Inst in $(seq $Concurrency)
  do
    while [[ ! -e accounts_${Inst}_done.txt ]];
    do
      sleep 1
    done
  done
}

function CreateAccountsAndTransactions
{
  count_start=$2
  # saw a few of these: might just be me
  # tr: write error
  # tr: write error: Connection reset by peer

  echo Working on $1

  echo Creating Keys for $1
  NewFile ${1}_names.txt
  NewFile ${1}_keys.txt
  NewFile ${1}_run.txt

  for Unused in $(seq $NumberOfAccounts)
  do
    echo create key >> ${1}_run.txt
  done
  eosc - < ${1}_run.txt | grep public | sed 's/^.* //' >> ${1}_keys.txt

  echo Creating Accounts for $1
  echo $(printf "%s " {a..z}) | awk -v "c=$NumberOfAccounts" -v "cstart=$count_start" '{
    countup=1
    for (v1 = 1; v1 <= NF; v1++)
      for (v2 = 1; v2 <= NF; v2++)
        for (v3 = 1; v3 <= NF; v3++)
          for (v4 = 1; v4 <= NF; v4++)
            for (v5 = 1; v5 <= NF; v5++)
              for (v6 = 1; v6 <= NF; v6++)
                for (v7 = 1; v7 <= NF; v7++)
                  for (v8 = 1; v8 <= NF; v8++)
                  {
                    if(countup >= cstart) 
		    {
		      printf( "test%c%c%c%c%c%c%c%c\n", $v1, $v2, $v3, $v4, $v5, $v6, $v7, $v8)
                      if((c-=1) == 0) exit
		    }
		    countup += 1
                  }
  }' > ${1}_names.txt
  ((count_start += NumberOfAccounts))

  NewFile ${1}_run.txt
  NewFile ${1}_create_results.txt
  for Row in $(paste -d',' ${1}_names.txt ${1}_keys.txt)
  do
    Name=$(echo $Row | awk -F',' '{print $1}')
    PubKey=$(echo $Row | awk -F',' '{print $2}')
    echo create account inita $Name $PubKey EOS6KdkmwhPyc2wxN9SAFwo2PU2h74nWs7urN1uRduAwkcns2uXsa >/dev/null 2>/dev/null >> ${1}_run.txt
  done
  eosc - < ${1}_run.txt >${1}_create_results.txt

  echo Preparing Transactions for $1
  NewFile ${1}_trx.txt
  for Name in $(cat ${1}_names.txt)
  do
    echo transfer eos $Name 1 >> ${1}_trx.txt
  done
  touch ${1}_done.txt
}

function RunOneCapTest
{
  ((eosc_call_count=0))
  NewFile ${1}_eosc_call_count.txt
  NewFile ${1}_trx_results.txt
  while :
  do
    ((eosc_call_count+=1))
    # Now=$(date +%s)
    # doesnt work, my output file disapears
    # timeout -sINT $((TestStop - Now)) ksh -c "eosc - < ${1}_trx.txt" >> ${1}_trx_results.txt 2>&1
    # apparently we cannot send a signal to fluch its output, using stdbuf until eosc can be worked on
    # stdbuf -i 0 -o 0 -e 0 eosc - < ${1}_trx.txt >> ${1}_trx_results.txt 2>>${1}_trx_results.txt
    # the above did not work, any other good suggestions?
    # okay, so we try to make it match as close as we can and tell the user the actual DurationSeconds time, it will be different from the one they want
    eosc - < ${1}_trx.txt >> ${1}_trx_results.txt 2>&1
    (( $(date +%s) >= TestStop )) && break
  done
  echo $eosc_call_count > ${1}_eosc_call_count.txt
  touch ${1}_done.txt
}

#
# Create Accounts
#
if [[ $1 != 0 ]]; then
  ((count_start_offset=1))
  RemoveDone
  for Inst in $(seq $Concurrency)
  do
    CreateAccountsAndTransactions accounts_${Inst} $count_start_offset &
    ((count_start_offset+=NumberOfAccounts))
  done
  WaitDone
fi

echo ----------------------------------
echo About to start capacity test, waiting 5 seconds for the load-average to go down.
sleep 5

#
# Begin capacity test
#
echo ----------------------------------
echo Starting Capacity Test $(date "+%Y%m%d_%H%M%S")
RemoveDone
TestStop=$(date +%s)
((TestStop=TestStop+DurationSeconds))
for Inst in $(seq $Concurrency); do; RunOneCapTest accounts_${Inst} &; done
if [[ $# == 4 ]]; then
  tail -f "$PathToEOSD_stdoutFile" 2>&1 | grep --line-buffered _generate_block 2>&1 | grep --line-buffered perf 2>&1 &
  tailpid=$!
fi
WaitDone
[[ $# == 4 ]] && kill -9 $tailpid


Now=$(date +%s)
((DurationSeconds=DurationSeconds + (Now - TestStop)))

echo End Capacity Test $(date "+%Y%m%d_%H%M%S") - Note: Took $DurationSeconds seconds to complete
echo ----------------------------------

#
# Report the results
#
((TrxAttempted=0))
for Inst in $(seq $Concurrency)
do
  Tmp=$(awk '/transaction_id|^[0-9][0-9]* assert_exception: Assert Exception/' accounts_${Inst}_trx_results.txt | wc -l)
  ((TrxAttempted += Tmp))
  echo $Tmp > accounts_${Inst}_trx_attempt_count.txt
done

((TrxSuccess=0))
for Inst in $(seq $Concurrency)
do
  Tmp=$(grep $GrepSearchForSuccess accounts_${Inst}_trx_results.txt | wc -l)
  ((TrxSuccess += Tmp))
done

sleep 1
echo Review \*_trx_results.txt for results of each transaction
echo Review \*_create_results.txt for results of each account creation transaction
echo There were $TrxSuccess successful transactions in $DurationSeconds seconds
echo There were supposed to be $TrxAttempted successful transactions
echo That comes to $(echo "scale=2; $TrxSuccess / $DurationSeconds" | bc -l) successful transactions per second
echo That comes to $(echo "scale=2; $TrxAttempted / $DurationSeconds" | bc -l) total transactions per second
echo ----------------------------------
echo The following instances ran eosc X times and had X transactons attempted
for Inst in $(seq $Concurrency)
do
  echo "For accounts_${Inst}, eosc ran $(cat accounts_${Inst}_eosc_call_count.txt) times and had $(cat accounts_${Inst}_trx_attempt_count.txt) attempted transactions"
done

