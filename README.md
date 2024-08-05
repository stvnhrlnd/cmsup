# CMSup

Just a little Bash script to prepare a Ubuntu system for Umbraco source debugging. Does the following:

- Installs the .NET SDK.
- Installs Node.js.
- Clones the Umbraco Git repository (or a fork).
- Adds the default starter kit.
- Builds the solution.
- Performs an unattended install of the CMS.

## Usage

Run the following command in your terminal:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/stvnhrlnd/cmsup/main/cmsup.sh | bash
```

By default it will clone the official [Umbraco-CMS](https://github.com/umbraco/Umbraco-CMS) Git repository into a directory named `Umbraco-CMS` in the current directory and check out the `contrib` branch. The default admin email is `admin@example.com` and the password is `1234567890`. All of this is configurable through command line arguments:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/stvnhrlnd/cmsup/main/cmsup.sh | bash -s -- \
  --repo https://github.com/umbraco/Umbraco-CMS.git \
  --branch contrib \
  --dir ./Umbraco-CMS \
  --admin-name Admnistrator \
  --admin-email admin@example.com \
  --admin-pass 1234567890
```

The Umbraco application is left running at the end so you can attach a debugger to it. Alternatively it can be killed with `Ctrl+C` and relaunched from your favourite IDE.

## Obligatory Terminal Screenshot

![CMSup executing in a terminal window.](/screenshot.png)

## But Why?

When I'm researching security issues in Umbraco I like to spin up clean VMs so I don't pollute my host system with dev dependencies and such. Also sometimes I break stuff and need to start over. So I wanted a one-liner that I could run on a freshly spun up VM that would provide me with a demo site I could debug as quick as possible.

I also just wanted to try my hand at some Bash scripting and got a bit carried away!

I figured the script might also be useful for anyone who wants to contribute to Umbraco and runs Ubuntu, but make sure you read ["Are you sure?"](https://github.com/umbraco/Umbraco-CMS/blob/contrib/.github/BUILD.md#are-you-sure) before proceeding to use it.

## Disclaimer

This project is not endorsed by Umbraco HQ. It may break at any time. Any and all issues are mine to own 🙏.

I have only tested this on Ubuntu 24.04 LTS (via [Multipass](https://multipass.run/)) and currently only Umbraco 14 branches are supported. This fits my current use case, the rest be damned for now (but issues and PRs are welcome 😊).
