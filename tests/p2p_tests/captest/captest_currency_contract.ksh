#!/bin/ksh
# Capacity Test - Currency Contract

if [[ $# != 3 ]] && [[ $# != 4 ]]; then
  echo This is a capacity test using eosc
  echo Usage: captest_currency_contract.ksh NumberOfAccounts DurationSeconds Concurrency [PathToEOSD_stdoutFile]
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
  echo   captest_currency_contract.ksh 3000 12 1
  echo   captest_currency_contract.ksh 3000 12 1 eosd-stdout.txt
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
  echo Error: The 4th parameter file "$PathToEOSD_stdoutFile" could not be found or is not a file
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

# kill previous captest_currency_contract if it is still running
if [[ $(pgrep captest_currency_contract.ksh | wc -l) > 1 ]]; then
  for p in $(pgrep captest_currency_contract.ksh)
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

function CreateNames
{
  echo CreateNames, into ${1}_names.txt
  count_start=$2
  NewFile ${1}_names.txt
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
  touch ${1}_done.txt
}

function CreateKeys
{
  echo CreateKeys, running ${1}_keys_cmd.txt
  NewFile ${1}_keys.txt
  NewFile ${1}_keys_cmd.txt
  for Unused in $(seq $NumberOfAccounts)
  do
    echo create key >> ${1}_keys_cmd.txt
  done
  eosc - < ${1}_keys_cmd.txt | grep public | sed 's/^.* //' >> ${1}_keys.txt
  touch ${1}_done.txt
}

function CreateEOSAccounts
{
  echo CreateEOSAccounts, running ${1}_create_eos_acct_cmd.txt
  NewFile ${1}_create_eos_acct_cmd.txt
  NewFile ${1}_create_eos_acct_cmd_results.txt
  for Row in $(paste -d',' ${1}_names.txt ${1}_keys.txt)
  do
    Name=$(echo $Row | awk -F',' '{print $1}')
    PubKey=$(echo $Row | awk -F',' '{print $2}')
    echo create account inita $Name $PubKey EOS6KdkmwhPyc2wxN9SAFwo2PU2h74nWs7urN1uRduAwkcns2uXsa >/dev/null 2>/dev/null >> ${1}_create_eos_acct_cmd.txt
  done
  eosc - < ${1}_create_eos_acct_cmd.txt >${1}_create_eos_acct_cmd_results.txt
  touch ${1}_done.txt
}

function TransferToEOSAccounts
{
  echo TransferToEOSAccounts, running ${1}_eos_transfer_cmd.txt
  NewFile ${1}_eos_transfer_results.txt
  NewFile ${1}_eos_transfer_cmd.txt
  for Name in $(cat ${1}_names.txt)
  do
    echo transfer eos $Name 100000 >> ${1}_eos_transfer_cmd.txt
  done
  eosc - < ${1}_eos_transfer_cmd.txt >${1}_eos_transfer_results.txt
  touch ${1}_done.txt
}

function CurrencyContractTransfer
{
  echo CurrencyContractTransfer, running ${1}_currency_trx_cmd.txt
  NewFile ${1}_currency_trx_results.txt
  NewFile ${1}_currency_trx_cmd.txt
  NewFile ${1}_eosc_call_count.txt
  ((eosc_call_count=0))
  for Name in $(cat ${1}_names.txt)
  do
    #Note: I had to make a custom change to eosc.cpp for match mode to accept these, might not be an issue soon anyway.
    cat >> ${1}_currency_trx_cmd.txt <<EOF
exec currency transfer '{"from":"currency","to":"$Name","amount":"1"}' '["currency","$Name"]' '[{"account":"currency","permission":"active"}]'
exec currency transfer '{"from":"$Name","to":"currency","amount":"1"}' '["currency","$Name"]' '[{"account":"$Name","permission":"active"}]'
EOF
  done
  while :
  do
    ((eosc_call_count+=1))
    eosc --batch-nostop-onerrors - < ${1}_currency_trx_cmd.txt >>${1}_currency_trx_results.txt 2>&1
    (( $(date +%s) >= TestStop )) && break
  done
  echo $eosc_call_count > ${1}_eosc_call_count.txt
  touch ${1}_done.txt
}

############################################################
#
# Running main application
#

if [[ $1 != 0 ]]; then

  RemoveDone
  ((count_start_offset=1))
  for Inst in $(seq $Concurrency) 
  do
    CreateNames accounts_${Inst} $count_start_offset &
    ((count_start_offset+=NumberOfAccounts))
  done
  WaitDone

  RemoveDone
  for Inst in $(seq $Concurrency); do; CreateKeys accounts_${Inst} &; done;
  WaitDone

  RemoveDone
  for Inst in $(seq $Concurrency); do; CreateEOSAccounts accounts_${Inst} &; done;
  WaitDone

  RemoveDone
  for Inst in $(seq $Concurrency); do; TransferToEOSAccounts accounts_${Inst} &; done;
  WaitDone
  
  echo Creating currency account, and wait for a block to pass
  eosc create account testaaaaaaaa currency $(head -1 accounts_1_keys.txt) EOS6KdkmwhPyc2wxN9SAFwo2PU2h74nWs7urN1uRduAwkcns2uXsa >/dev/null 2>/dev/null
  sleep 4

  echo SetCode
  eosc setcode currency ../../../contracts/currency/currency.wast ../../../contracts/currency/currency.abi
  echo SetCode Done

  echo ----------------------------------
  echo About to start capacity test, waiting 5 seconds for the load-average to go down.
  sleep 5
fi

#
# Begin capacity test
#
echo ----------------------------------
echo Starting Capacity Test $(date "+%Y%m%d_%H%M%S")
RemoveDone
TestStop=$(date +%s)
((TestStop=TestStop+DurationSeconds))
for Inst in $(seq $Concurrency); do; CurrencyContractTransfer accounts_${Inst} &; done;
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
rm *_done.txt 2>/dev/null

#
# Report the results
#
((TrxAttempted=0))
for Inst in $(seq $Concurrency)
do
  Tmp=$(awk '/transaction_id|^[0-9][0-9]* assert_exception: Assert Exception/' accounts_${Inst}_currency_trx_results.txt | wc -l)
  ((TrxAttempted += Tmp))
  echo $Tmp > accounts_${Inst}_trx_attempt_count.txt
done

((TrxSuccess=0))
for Inst in $(seq $Concurrency)
do
  Tmp=$(grep $GrepSearchForSuccess accounts_${Inst}_currency_trx_results.txt | wc -l)
  ((TrxSuccess += Tmp))
done

sleep 1
echo Review \*_results.txt for results of each account creation transaction
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




