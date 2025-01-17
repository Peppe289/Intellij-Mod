#!/bin/sh
# Copyright 2000-2023 JetBrains s.r.o. and contributors. Use of this source code is governed by the Apache 2.0 license.

# ---------------------------------------------------------------------
# IntelliJ IDEA startup script.
# ---------------------------------------------------------------------

message()
{
  TITLE="Cannot start IntelliJ IDEA"
  if [ -n "$(command -v zenity)" ]; then
    zenity --error --title="$TITLE" --text="$1" --no-wrap
  elif [ -n "$(command -v kdialog)" ]; then
    kdialog --error "$1" --title "$TITLE"
  elif [ -n "$(command -v notify-send)" ]; then
    notify-send "ERROR: $TITLE" "$1"
  elif [ -n "$(command -v xmessage)" ]; then
    xmessage -center "ERROR: $TITLE: $1"
  else
    printf "ERROR: %s\n%s\n" "$TITLE" "$1"
  fi
}

if [ -z "$(command -v uname)" ] || [ -z "$(command -v realpath)" ] || [ -z "$(command -v dirname)" ] || [ -z "$(command -v cat)" ] || \
   [ -z "$(command -v grep)" ]; then
  TOOLS_MSG="Required tools are missing:"
  for tool in uname realpath grep dirname cat ; do
     test -z "$(command -v $tool)" && TOOLS_MSG="$TOOLS_MSG $tool"
  done
  message "$TOOLS_MSG (SHELL=$SHELL PATH=$PATH)"
  exit 1
fi

# shellcheck disable=SC2034
GREP_OPTIONS=''
OS_TYPE=$(uname -s)
OS_ARCH=$(uname -m)

# ---------------------------------------------------------------------
# Ensure $IDE_HOME points to the directory where the IDE is installed.
# ---------------------------------------------------------------------
IDE_BIN_HOME=$(dirname "$(realpath "$0")")
IDE_HOME=$(dirname "${IDE_BIN_HOME}")
CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"

# ---------------------------------------------------------------------
# Locate a JRE installation directory command -v will be used to run the IDE.
# Try (in order): $IDEA_JDK, .../idea.jdk, .../jbr, $JDK_HOME, $JAVA_HOME, "java" in $PATH.
# ---------------------------------------------------------------------
JRE=""

# shellcheck disable=SC2154
if [ -n "$IDEA_JDK" ] && [ -x "$IDEA_JDK/bin/java" ]; then
  JRE="$IDEA_JDK"
fi

if [ -z "$JRE" ] && [ -s "${CONFIG_HOME}/JetBrains/IntelliJIdea2024.1/idea.jdk" ]; then
  USER_JRE=$(cat "${CONFIG_HOME}/JetBrains/IntelliJIdea2024.1/idea.jdk")
  if [ -x "$USER_JRE/bin/java" ]; then
    JRE="$USER_JRE"
  fi
fi

if [ -z "$JRE" ] && [ "$OS_TYPE" = "Linux" ] && [ -f "$IDE_HOME/jbr/release" ]; then
  JBR_ARCH="OS_ARCH=\"$OS_ARCH\""
  if grep -q -e "$JBR_ARCH" "$IDE_HOME/jbr/release" ; then
    JRE="$IDE_HOME/jbr"
  fi
fi

# shellcheck disable=SC2153
if [ -z "$JRE" ]; then
  if [ -n "$JDK_HOME" ] && [ -x "$JDK_HOME/bin/java" ]; then
    JRE="$JDK_HOME"
  elif [ -n "$JAVA_HOME" ] && [ -x "$JAVA_HOME/bin/java" ]; then
    JRE="$JAVA_HOME"
  fi
fi

if [ -z "$JRE" ]; then
  JAVA_BIN=$(command -v java)
else
  JAVA_BIN="$JRE/bin/java"
fi

if [ -z "$JAVA_BIN" ] || [ ! -x "$JAVA_BIN" ]; then
  message "No JRE found. Please make sure \$IDEA_JDK, \$JDK_HOME, or \$JAVA_HOME point to valid JRE installation."
  exit 1
fi

# ---------------------------------------------------------------------
# Collect JVM options and IDE properties.
# ---------------------------------------------------------------------
IDE_PROPERTIES_PROPERTY=""
# shellcheck disable=SC2154
if [ -n "$IDEA_PROPERTIES" ]; then
  IDE_PROPERTIES_PROPERTY="-Didea.properties.file=$IDEA_PROPERTIES"
fi

VM_OPTIONS_FILE=""
USER_VM_OPTIONS_FILE=""
# shellcheck disable=SC2154
if [ -n "$IDEA_VM_OPTIONS" ] && [ -r "$IDEA_VM_OPTIONS" ]; then
  # 1. $<IDE_NAME>_VM_OPTIONS
  VM_OPTIONS_FILE="$IDEA_VM_OPTIONS"
else
  # 2. <IDE_HOME>/bin/[<os>/]<bin_name>.vmoptions ...
  if [ -r "${IDE_BIN_HOME}/idea64.vmoptions" ]; then
    VM_OPTIONS_FILE="${IDE_BIN_HOME}/idea64.vmoptions"
  else
    test "${OS_TYPE}" = "Darwin" && OS_SPECIFIC="mac" || OS_SPECIFIC="linux"
    if [ -r "${IDE_BIN_HOME}/${OS_SPECIFIC}/idea64.vmoptions" ]; then
      VM_OPTIONS_FILE="${IDE_BIN_HOME}/${OS_SPECIFIC}/idea64.vmoptions"
    fi
  fi
  # ... [+ <IDE_HOME>.vmoptions (Toolbox) || <config_directory>/<bin_name>.vmoptions]
  if [ -r "${IDE_HOME}.vmoptions" ]; then
    USER_VM_OPTIONS_FILE="${IDE_HOME}.vmoptions"
  elif [ -r "${CONFIG_HOME}/JetBrains/IntelliJIdea2024.1/idea64.vmoptions" ]; then
    USER_VM_OPTIONS_FILE="${CONFIG_HOME}/JetBrains/IntelliJIdea2024.1/idea64.vmoptions"
  fi
fi

VM_OPTIONS=""
USER_GC=""
if [ -n "$USER_VM_OPTIONS_FILE" ]; then
  grep -E -q -e "-XX:\+.*GC" "$USER_VM_OPTIONS_FILE" && USER_GC="yes"
fi
if [ -n "$VM_OPTIONS_FILE" ] || [ -n "$USER_VM_OPTIONS_FILE" ]; then
  if [ -z "$USER_GC" ] || [ -z "$VM_OPTIONS_FILE" ]; then
    VM_OPTIONS=$(cat "$VM_OPTIONS_FILE" "$USER_VM_OPTIONS_FILE" 2> /dev/null | grep -E -v -e "^#.*")
  else
    VM_OPTIONS=$({ grep -E -v -e "-XX:\+Use.*GC" "$VM_OPTIONS_FILE"; cat "$USER_VM_OPTIONS_FILE"; } 2> /dev/null | grep -E -v -e "^#.*")
  fi
else
  message "Cannot find a VM options file"
fi

CLASS_PATH="$IDE_HOME/lib/platform-loader.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/util-8.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/util.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/app-client.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/util_rt.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/product.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/opentelemetry.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/app.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/product-client.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/modules.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/lib-client.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/stats.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/jps-model.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/external-system-rt.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/rd.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/bouncy-castle.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/protobuf.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij-test-discovery.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij-coverage-agent-1.0.744.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/forms_rt.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/lib.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/externalProcess-rt.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/groovy.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/annotations.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/async-profiler.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/grpc.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/idea_rt.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/jsch-agent.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/junit4.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/nio-fs.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/trove.jar"

# ---------------------------------------------------------------------
# Run the IDE.
# ---------------------------------------------------------------------
IFS="$(printf '\n\t')"
# shellcheck disable=SC2086

# [MOD]
# Initialize variables to store RAM limit and CPU affinity values.
RAM_UNITY_VAL=""
MEMORY_FLAGS_ARGS=""
CPU_SET_ARGS=""

# Function to handle errors and exit the script.
# Prints the error message passed as an argument and exits with a status of 1.
# Arguments:
#   $1 - The error message to display.
error_func() {
    echo "Error: $1" >&2
    exit 1
}

# Function to extract the value after the equal sign in a parameter.
# This function assumes the parameter is in the format 'key=value' and extracts 'value'.
# Arguments:
#   $1 - The parameter from which to extract the value.
# Outputs:
#   Prints the value extracted from the parameter.
get_value() {
    local param="$1"
    echo "$param" | cut -d= -f2
}

# Function to validate if the CPU set input is in the correct format (numbers and commas).
# If the input is invalid, it calls error_func to exit the script.
# Arguments:
#   $1 - The input string representing the CPU set.
validate_cpu_set() {
    local input="$1"
    local pattern='^[0-9,]+$'
    
    if ! [[ $input =~ $pattern ]]; then
        error_func "Invalid input as CPU set"
    fi
}

# Function to log custom messages.
# Arguments:
#   $1 - The message to log.
customLog() {
    echo "### [MOD]: ${1}"
}

# Loop through the arguments passed to the script.
# Processes known options and extracts their values.
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help_mod)
            # Display help message and exit.
            echo "./idea_mod.sh - Custom profile"
            echo " "
            echo "env [ENV] ./idea_mod.sh"
            echo " "
            echo "Possibile ENV var: "
            echo "env RAM_LIMIT -> for limit RAM usage for example for give only 1GB:"
            echo "                  env RAM_LIMIT=1G ./idea_mod.sh"
            echo "env CORE_AFFINITY -> for force CPU affinity for example for give only core 1,2,3:"
            echo "                  env CORE_AFFINITY=1,2,3 ./idea_mod.sh"
            exit 0
        ;;
    esac
done

# Check if RAM_LIMIT is set and process it.
if [ "$RAM_LIMIT" != "" ]; then
    # Extract the last character to determine the unit (G or M).
    RAM_UNITY_VAL=$(echo "$RAM_LIMIT" | awk '{print substr($0, length, 1)}')
    # Remove the last character from RAM_LIMIT.
    RAM_LIMIT=${RAM_LIMIT::-1}
    
    # Validate that RAM_LIMIT is a number.
    re='^[0-9]+$'
    if ! [[ $RAM_LIMIT =~ $re ]]; then
        error_func "Not a number"
    fi
    
    # Determine the RAM unit and log it.
    case $RAM_UNITY_VAL in
        "G")
            customLog "Set RAM unit as gigabytes"
        ;;
        "M")
            customLog "Set RAM unit as megabytes"
        ;;
        *)
            error_func "Invalid unit value"
        ;;
    esac

    # Log the RAM limit value.
    customLog "RAM LIMIT: ${RAM_LIMIT}"
    MEMORY_FLAGS_ARGS="systemd-run --scope -p MemoryLimit=$RAM_LIMIT$RAM_UNITY_VAL"
fi

# Check if CORE_AFFINITY is set and process it.
if [ "$CORE_AFFINITY" != "" ]; then
    # Validate the CPU set format.
    validate_cpu_set $CORE_AFFINITY
    # Log the CPU affinity value.
    customLog "CPU AFFINITY: $CORE_AFFINITY"
    CPU_SET_ARGS="taskset -c $CORE_AFFINITY"
    customLog "Start with $CPU_SET_ARGS"
fi

# ---------------------------------------------------------------------
# MOD: limit RAM usage
# ---------------------------------------------------------------------
# Since since `-Xmx512m -Xms512m -Xss512m` doesn't work well with what we want to do,
# we can directly use linux services to give less ram.
# ---------------------------------------------------------------------
eval exec "$MEMORY_FLAGS_ARGS" "$CPU_SET_ARGS" "$JAVA_BIN" \
  -classpath "$CLASS_PATH" \
  "-XX:ErrorFile=$HOME/java_error_in_idea_%p.log" \
  "-XX:HeapDumpPath=$HOME/java_error_in_idea_.hprof" \
  ${VM_OPTIONS} \
  "-Djb.vmOptionsFile=${USER_VM_OPTIONS_FILE:-${VM_OPTIONS_FILE}}" \
  ${IDE_PROPERTIES_PROPERTY} \
  -Djava.system.class.loader=com.intellij.util.lang.PathClassLoader -Didea.vendor.name=JetBrains -Didea.paths.selector=IntelliJIdea2024.1 "-Djna.boot.library.path=$IDE_HOME/lib/jna/amd64" "-Dpty4j.preferred.native.folder=$IDE_HOME/lib/pty4j" -Djna.nosys=true -Djna.noclasspath=true "-Dintellij.platform.runtime.repository.path=$IDE_HOME/modules/module-descriptors.jar" -Dsplash=true -Daether.connector.resumeDownloads=false --add-opens=java.base/java.io=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.lang.ref=ALL-UNNAMED --add-opens=java.base/java.lang.reflect=ALL-UNNAMED --add-opens=java.base/java.net=ALL-UNNAMED --add-opens=java.base/java.nio=ALL-UNNAMED --add-opens=java.base/java.nio.charset=ALL-UNNAMED --add-opens=java.base/java.text=ALL-UNNAMED --add-opens=java.base/java.time=ALL-UNNAMED --add-opens=java.base/java.util=ALL-UNNAMED --add-opens=java.base/java.util.concurrent=ALL-UNNAMED --add-opens=java.base/java.util.concurrent.atomic=ALL-UNNAMED --add-opens=java.base/java.util.concurrent.locks=ALL-UNNAMED --add-opens=java.base/jdk.internal.vm=ALL-UNNAMED --add-opens=java.base/sun.nio.ch=ALL-UNNAMED --add-opens=java.base/sun.nio.fs=ALL-UNNAMED --add-opens=java.base/sun.security.ssl=ALL-UNNAMED --add-opens=java.base/sun.security.util=ALL-UNNAMED --add-opens=java.base/sun.net.dns=ALL-UNNAMED --add-opens=java.desktop/com.sun.java.swing.plaf.gtk=ALL-UNNAMED --add-opens=java.desktop/java.awt=ALL-UNNAMED --add-opens=java.desktop/java.awt.dnd.peer=ALL-UNNAMED --add-opens=java.desktop/java.awt.event=ALL-UNNAMED --add-opens=java.desktop/java.awt.image=ALL-UNNAMED --add-opens=java.desktop/java.awt.peer=ALL-UNNAMED --add-opens=java.desktop/java.awt.font=ALL-UNNAMED --add-opens=java.desktop/javax.swing=ALL-UNNAMED --add-opens=java.desktop/javax.swing.plaf.basic=ALL-UNNAMED --add-opens=java.desktop/javax.swing.text=ALL-UNNAMED --add-opens=java.desktop/javax.swing.text.html=ALL-UNNAMED --add-opens=java.desktop/sun.awt.X11=ALL-UNNAMED --add-opens=java.desktop/sun.awt.datatransfer=ALL-UNNAMED --add-opens=java.desktop/sun.awt.image=ALL-UNNAMED --add-opens=java.desktop/sun.awt=ALL-UNNAMED --add-opens=java.desktop/sun.font=ALL-UNNAMED --add-opens=java.desktop/sun.java2d=ALL-UNNAMED --add-opens=java.desktop/sun.swing=ALL-UNNAMED --add-opens=java.desktop/com.sun.java.swing=ALL-UNNAMED --add-opens=jdk.attach/sun.tools.attach=ALL-UNNAMED --add-opens=jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED --add-opens=jdk.internal.jvmstat/sun.jvmstat.monitor=ALL-UNNAMED --add-opens=jdk.jdi/com.sun.tools.jdi=ALL-UNNAMED \
  com.intellij.idea.Main \
  "$@"
