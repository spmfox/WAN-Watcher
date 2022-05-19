#!/bin/bash
#spmfox@foxwd.com
#wan-watcher.sh

#This script checks the current WAN IP address and optionally does further checks. 
#Run using -d for all output, otherwise the default will be to only output for alerts. Exit code will be 0 for clean and 1 for alert.
#Alerts can be easily configurd by using https://github.com/spmfox/systemd-alerts.

#Commands used:
#curl
#whois
#host

#Features:
#Check for WAN IP change (main feature)
#Check for WAN provider change (optional)
#Check for expected DNS name, for custom dynamic DNS checks (optional)
#Curl out to update dynamic DNS with external provider (optional)

#URL of a website that will return *ONLY* the current WAN IP address as *ONLY* text.
#This is required.
IPcheckURL=""

#Dynamic DNS name to check current WAN IP against.
#Does nothing if blank.
ExpectedDNSname=""

#Specific DNS server to check the dynamic DNS name.
#Optional
DNSserver=""

#We will grep the OrgName of a whois output to determine if the WAN changed providers.
#To be cautious about rate-limits, this will ONLY be done when an IP change is detected.
#Does nothing if blank.
ExpectedOrgNameGrep=""

#We will curl this to keep dynamic DNS up-to-date.
#Does nothing if blank.
DynamicDNScurl=""

#This overrides the dynamic DNS curl if the last known provider was not the expected one.
#Does nothing if blank, wont work if ExpectedOrgNameGrep is blank.
DynamicDNSproviderOverride=""

#This directory will be used to store the last known IP address and provider.
#This is required.
TempDir=""

#If this variable is set, then a missing IP address file will trigger a failure..
#Does nothing if left blank.
AlertIPfileMissing=""

if [ "$1" == "-d" ]; then
  Debug="true"
fi

function output {
  Alert=$(echo "$1" | grep "WARN\|FATAL")
  if [ -n "$Debug" ] || [ -n "$Alert" ]; then
    echo $1
  fi
  if [ -n "$Alert" ]; then
    ExitError=yes
  fi
}

function quit {
  if [ -n "$ExitError" ]; then
    exit 1
  else
    exit 0
  fi
}

if [ -z "$TempDir" ]; then
  output "FATAL: TempDir needs to be defined."
  quit
fi

CurrentIP=$(curl -s $IPcheckURL)
output "DEBUG: Current IP is ($CurrentIP)."
if [ -e "$TempDir/.wan-watcher-ip" ] && [ -e "$TempDir/.wan-watcher-provider" ]; then
  LastKnownIP=$(cat "$TempDir/.wan-watcher-ip")
  if [ "$CurrentIP" == "$LastKnownIP" ]; then
    output "DEBUG: Current IP ($CurrentIP) matches last known IP ($LastKnownIP)."
  else
    output "WARN: Current IP ($CurrentIP) does NOT match last known IP ($LastKnownIP)."
    WhoisCheck="yes"
    echo "$CurrentIP" > "$TempDir/.wan-watcher-ip"
  fi
else
  if [ -n "$AlertIPfileMissing" ]; then
    output "WARN: Last known IP is missing, writing new file."
  else
    output "DEBUG: Last known IP is missing, writing new file."
  fi
  WhoisCheck="yes"
  echo "$CurrentIP" > "$TempDir/.wan-watcher-ip"
fi

if [ -n "$ExpectedDNSname" ]; then
  output "DEBUG: Executing (nslookup $ExpectedDNSname $DNSserver) to check current DNS name."
  CurrentDNSlookup=$(host "$ExpectedDNSname" "$DNSserver" |grep "address" |awk -F "address" '{print $2}' |xargs)
  if [ "$CurrentIP" == "$CurrentDNSlookup" ]; then
    output "DEBUG: Expected DNS name ($ExpectedDNSname)($CurrentDNSlookup) resolves to current IP ($CurrentIP)."
  else
    output "WARN: Expected DNS name ($ExpectedDNSname)($CurrentDNSlookup) does NOT resolve to current IP ($CurrentIP)."
  fi
else
    output "DEBUG: Skipping expected DNS check, variable (ExpectedDNSname) not set."
fi

if [ -n "$WhoisCheck" ]; then
  if [ -n "$ExpectedOrgNameGrep" ]; then
    output "DEBUG: Executing (whois $CurrentIP |grep OrgName |grep $ExpectedOrgNameGrep)."
    CurrentWhoisLookup=$(whois "$CurrentIP" |grep OrgName: |awk -F "OrgName:" '{print $2}' |xargs)
    CurrentWhoisLookupCheck=$(echo "$CurrentWhoisLookup" |grep "$ExpectedOrgNameGrep")
    echo "$CurrentWhoisLookup" > "$TempDir/.wan-watcher-provider"
    if [ -n "$CurrentWhoisLookupCheck" ]; then
      output "DEBUG: Expected OrgName ($ExpectedOrgNameGrep) matches whois lookup OrgName ($CurrentWhoisLookup)."
    else
      output "WARN: Expected OrgName ($ExpectedOrgNameGrep) does NOT match whois lookup OrgName ($CurrentWhoisLookup)."
    fi
  else
    output "DEBUG: Skipping triggered whois check, variable (ExpectedOrgNameGrep) is not set."
  fi
else
  output "DEBUG: Whois check not triggered."
fi

if [ -n "$DynamicDNScurl" ]; then
  if [ -n "$DynamicDNSproviderOverride" ] && [ -n "$ExpectedOrgNameGrep" ]; then
    LastKnownWhoisLookup=$(cat "$TempDir/.wan-watcher-provider")
    LastKnownWhoisLookupCheck=$(echo "$LastKnownWhoisLookup" |grep "$ExpectedOrgNameGrep")
    if [ -n "$LastKnownWhoisLookupCheck" ]; then
      output "DEBUG: Executing dynamic DNS update, DynamicDNSproviderOverride was set and the last known provider ($LastKnownWhoisLookup) matches expected provider ($ExpectedOrgNameGrep)."
      DynamicDNScurl=$(curl -s $DynamicDNScurl)
      output "DEBUG: Dynamic DNS response was ($DynamicDNScurl)."
    else
      output "DEBUG: Skipping dynamic DNS update, last known provider ($LastKnownWhoisLookup) does NOT match expected provider ($ExpectedOrgNameGrep)."
    fi
  else
    output "DEBUG: Executing dynamic DNS update (curl $DynamicDNScurl)."
    DynamicDNScurl=$(curl -s $DynamicDNScurl)
    output "DEBUG: Dynamic DNS response was ($DynamicDNScurl)."
  fi
else
  output "DEBUG: Skipping dynamic DNS update, variable (DynamicDNScurl) is not set."
fi

quit
