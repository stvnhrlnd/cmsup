#!/bin/bash

# ---------------------------------------------------------------------------- #
#                                 Shell Options                                #
# ---------------------------------------------------------------------------- #

# This section of code was lifted from this project:
#   https://github.com/ralish/bash-script-template

# For an explanation of the options see this article:
#   https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
  set -o xtrace # Trace the execution of the script (debug)
fi

# Only enable these shell behaviours if we're not being sourced
# Approach via: https://stackoverflow.com/a/28776166/8787985
if ! (return 0 2>/dev/null); then
  # A better class of script...
  set -o errexit  # Exit on most errors (see the manual)
  set -o nounset  # Disallow expansion of unset variables
  set -o pipefail # Use last non-zero exit code in a pipeline
fi

# Enable errtrace or the error trap handler will not work as expected
set -o errtrace # Ensure the error trap handler is inherited

# ---------------------------------------------------------------------------- #
#                                   Functions                                  #
# ---------------------------------------------------------------------------- #

# DESC: The most important function of them all - print the ASCII banner
function cmsup_banner() {
  cat <<EOF
 _____ _____ _____
|     |     |   __|_ _ ___
|   --| | | |__   | | | . |
|_____|_|_|_|_____|___|  _| v0.1.0
                      |_|
EOF
}

# DESC: Show the script help message
function cmsup_usage() {
  cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [--repo REPO] [--branch BRANCH] [--dir DIR]
                [--admin-name NAME] [--admin-email EMAIL] [--admin-pass PASS]

Clone and build Umbraco CMS from source. Installs the .NET SDK and Node.js and
performs an unattended install including the default starter kit.

Options:
  -h, --help           Show this help message
  --repo REPO          URL of the Umbraco Git repository to clone (default: https://github.com/umbraco/Umbraco-CMS.git)
  --branch BRANCH      Name of the Git branch to check out (default: contrib)
  --dir DIR            Local directory for the Git repo (default: ./Umbraco-CMS)
  --admin-name NAME    Friendly name for the admin user (default: Administrator)
  --admin-email EMAIL  Email address for the admin user (default: admin@example.com)
  --admin-pass PASS    Password for the admin user (default: 1234567890)
EOF
}

# DESC: Print a message to stdout with a new line
# ARGS: $1 (required): Message to print
function cmsup_print() {
  local -r message="$1"
  printf '%s\n' "${message}"
}

# DESC: Print an informational message
# ARGS: $1 (required): Message to print
function cmsup_print_info() {
  local -r message="$1"
  cmsup_print "[*] ${message}"
}

# DESC: Print an error message to stderr
# ARGS: $1 (required): Message to print
function cmsup_print_error() {
  local -r message="$1"
  cmsup_print "[!] ${message}" >&2
}

# DESC: Handler for unexpected errors
function cmsup_trap_err() {
  # Disable the error trap handler to prevent potential recursion
  trap - ERR

  # Consider any further errors non-fatal to ensure we run to completion
  set +o errexit
  set +o pipefail

  # Exit with failure status
  exit 1
}

# DESC: Check if a command exists on the system
# ARGS: $1 (required): Command to check
function cmsup_is_command() {
  local -r command="$1"
  command -v "${command}" >/dev/null 2>&1
}

# DESC: Download a file using curl and write contents to stdout
# ARGS: $1 (required): URL of the file
function cmsup_download() {
  local -r file="$1"

  # Enforce HTTPS with TLSv1.2 or above, be silent unless there are errors, and
  # follow redirects.
  curl --proto '=https' --tlsv1.2 -sSf --location "${file}"
}

# DESC: Install the .NET SDK
function cmsup_install_dotnet_sdk() {
  if cmsup_is_command dotnet && [[ -n $(dotnet --list-sdks) ]]; then
    # TODO: Check that at least one installed SDK meets the minimum version
    #       required by Umbraco.
    cmsup_print_info '.NET SDKs detected:'
    dotnet --list-sdks
  else
    cmsup_print_info 'Installing the .NET SDK...'
    sudo apt-get update
    sudo apt-get install -y dotnet-sdk-8.0

    # TODO: I originally wanted to use the dotnet-install script from Microsoft to
    #       perform a non-root installation that didn't require sudo or apt (for
    #       better cross-platform support).
    #
    #       The old code is commented out below. It worked, but for some reason the
    #       C# extension for VS Code couldn't find the dotnet executable despite it
    #       being added to the PATH. So to hell with edge cases for now, apt it is.
    #
    #       Similar issue: https://github.com/microsoft/vscode-dotnettools/issues/637

    # local -r dotnet_install_script_url='https://dot.net/v1/dotnet-install.sh'
    # local -r dotnet_install_dir="${HOME}/.dotnet"
    # local -r shell_profile="${HOME}/.bashrc"

    # cmsup_download "${dotnet_install_script_url}" | bash -s -- \
    #   --channel LTS --install-dir "${dotnet_install_dir}" --no-path

    # # Update shell profile so that dotnet is added to the current user's PATH
    # local -r export_command="export PATH='${dotnet_install_dir}':\${PATH}"
    # if ! grep --quiet "${export_command}" "${shell_profile}"; then
    #   printf '\n%s\n' "${export_command}" >>"${shell_profile}"
    # fi

    # # Ensure dotnet is available for the build step
    # export PATH="${dotnet_install_dir}":${PATH}
  fi
}

# DESC: Install the Node Version Manager and Node.js
function cmsup_install_nodejs() {
  local -r nvm_install_script_url='https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh'
  local -r nvm_install_dir="${HOME}/.nvm"
  local -r nodejs_version=20 # LTS

  if cmsup_is_command node && cmsup_is_command npm; then
    # TODO: Check minimum version requirements are met
    cmsup_print_info "Node.js detected: $(node --version || true)"
    cmsup_print_info "NPM detected: $(npm --version || true)"
  else
    cmsup_print_info 'Installing Node Version Manager...'

    cmsup_download "${nvm_install_script_url}" | bash

    # Source the nvm script so that the nvm command is brought into scope
    # shellcheck source=/dev/null
    source "${nvm_install_dir}/nvm.sh"

    cmsup_print_info 'Installing Node.js...'
    nvm install "${nodejs_version}"
  fi
}

# DESC: Clone a Git repository and its submodules
# ARGS: $1 (required): URL of the Git repository to clone
#       $2 (required): Name of the branch to check out
#       $3 (required): Local directory for the Git repo
function cmsup_clone_repo() {
  local -r repo="$1"
  local -r branch="$2"
  local -r dir="$3"
  cmsup_print_info 'Cloning the repository...'
  git clone --branch "${branch}" "${repo}" "${dir}"
  git -C "${dir}" submodule update --init
}

# DESC: Build Umbraco and do an unattended install including the default starter kit
# ARGS: $1 (required): Directory of the local Umbraco repository
#       $2 (required): Friendly name for the admin user
#       $3 (required): Email address for the admin user
#       $4 (required): Password for the admin user
function cmsup_install_umbraco() {
  local -r dir="$1"
  local -r admin_name="$2"
  local -r admin_email="$3"
  local -r admin_pass="$4"

  local -r sln_file="${dir}/umbraco.sln"
  local -r project_dir="${dir}/src/Umbraco.Web.UI"
  local -r project_file="${project_dir}/Umbraco.Web.UI.csproj"
  local -r appsettings_file="${project_dir}/appsettings.json"
  local -r umbraco_dbsn='Data Source=|DataDirectory|/Umbraco.sqlite.db;Cache=Shared;Foreign Keys=True;Pooling=True'
  local -r umbraco_dbsn_provider_name='Microsoft.Data.Sqlite'

  cmsup_print_info 'Adding starter kit package...'
  dotnet add "${project_file}" package Umbraco.TheStarterKit

  cmsup_print_info 'Building the Umbraco solution. Go grab a coffee (or two)...'
  dotnet build "${sln_file}" /property:GenerateFullPaths=true /consoleloggerparameters:NoSummary

  cmsup_print_info 'Adding connection string settings to appsettings.json...'
  # NOTE: These settings *can* be passed as environment variables, which I would
  #       prefer to do, but the unattended install does not update the
  #       appsettings.json like a manual install does, so doing it this way for now
  #       and relying on jq (which comes pre-installed on Ubuntu at least).
  local -r new_appsettings_json=$(
    jq \
      --arg umbraco_dbsn "${umbraco_dbsn}" \
      --arg umbraco_dbsn_provider_name "${umbraco_dbsn_provider_name}" \
      '.ConnectionStrings.umbracoDbDSN = $umbraco_dbsn |
       .ConnectionStrings.umbracoDbDSN_ProviderName = $umbraco_dbsn_provider_name' \
      "${appsettings_file}"
  )
  printf '%s' "${new_appsettings_json}" >"${appsettings_file}"

  cmsup_print_info 'Running Umbraco unattended install...'
  Umbraco__CMS__Unattended__InstallUnattended=true \
    Umbraco__CMS__Unattended__UnattendedUserName="${admin_name}" \
    Umbraco__CMS__Unattended__UnattendedUserEmail="${admin_email}" \
    Umbraco__CMS__Unattended__UnattendedUserPassword="${admin_pass}" \
    dotnet run --project "${project_file}" /property:GenerateFullPaths=true /consoleloggerparameters:NoSummary
}

# DESC: Main entry point
# ARGS: $@ (optional): See usage for available arguments
function cmsup() {
  local repo='https://github.com/umbraco/Umbraco-CMS.git'
  local branch='contrib'
  local dir='./Umbraco-CMS'
  local admin_name='Administrator'
  local admin_email='admin@example.com'
  local admin_pass='1234567890'

  # Parse arguments
  # TODO: Some validation maybe? xD
  local param
  while [[ $# -gt 0 ]]; do
    param="$1"
    shift

    case "${param}" in
    -h | --help)
      cmsup_usage
      return 0
      ;;
    --repo)
      repo="$1"
      readonly repo
      shift
      ;;
    --branch)
      branch="$1"
      readonly branch
      shift
      ;;
    --dir)
      dir="$1"
      readonly dir
      shift
      ;;
    --admin-name)
      admin_name="$1"
      readonly admin_name
      shift
      ;;
    --admin-email)
      admin_email="$1"
      readonly admin_email
      shift
      ;;
    --admin-pass)
      admin_pass="$1"
      readonly admin_pass
      shift
      ;;
    *)
      cmsup_print_error "Invalid parameter: ${param}"
      return 2
      ;;
    esac
  done

  # Do all the things!
  cmsup_banner
  cmsup_print '=================================================='
  cmsup_print_info "Repository   : ${repo}"
  cmsup_print_info "Branch       : ${branch}"
  cmsup_print_info "Directory    : ${dir}"
  cmsup_print_info "Admin name   : ${admin_name}"
  cmsup_print_info "Admin email  : ${admin_email}"
  cmsup_print_info "Admin pass   : ${admin_pass}"
  cmsup_print '=================================================='
  cmsup_install_dotnet_sdk
  cmsup_print '=================================================='
  cmsup_install_nodejs
  cmsup_print '=================================================='
  cmsup_clone_repo "${repo}" "${branch}" "${dir}"
  cmsup_print '=================================================='
  cmsup_install_umbraco "${dir}" "${admin_name}" "${admin_email}" "${admin_pass}"
}

# ---------------------------------------------------------------------------- #
#                                  Let's go!!                                  #
# ---------------------------------------------------------------------------- #

# Invoke cmsup with args if not sourced
if ! (return 0 2>/dev/null); then
  trap cmsup_trap_err ERR
  cmsup "$@"
fi
