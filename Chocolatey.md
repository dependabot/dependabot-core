Chocolatey is a powerful package manager for Windows that simplifies the installation, updating, and management of software via the command line. It functions similarly to package managers like apt on Linux or brew on macOS, allowing users to automate software deployments and maintain consistency across systems.
GeeksforGeeks

### ⚙️ How to Install Chocolatey on Windows
### ✅ Prerequisites

Before installing Chocolatey, ensure the following:

1. Operating System: Windows 7 or later / Windows Server 2003 or later

2. PowerShell Version: 2.0 or higher

3. .NET Framework: 4.0 or later

4. Administrator Access: Required to run installation commands

### 🛠️ Installation Steps

#### Option 1: Using PowerShell

##### 1. Open PowerShell as Administrator:

  * Press Win + S, type "PowerShell", right-click on it, and select "Run as administrator".

##### 2. Set Execution Policy:

  * Check the current policy:

```powershell
Get-ExecutionPolicy
```
  * If it returns Restricted, change it to allow script execution:


```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
```
##### 3. Run the Installation Command:

  * Execute the following command to install Chocolatey:

```powershell

Set-ExecutionPolicy Bypass -Scope Process -Force; `
[System.Net.ServicePointManager]::SecurityProtocol = `
[System.Net.ServicePointManager]::SecurityProtocol -bor 3072; `
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
```
##### 4. Verify Installation:

  * After installation, close and reopen PowerShell, then run:

```powershell
choco -v
```
  * This should display the installed version of Chocolatey.

#### Option 2: Using Command Prompt (CMD)
##### 1. Open CMD as Administrator:

  * Press Win + S, type "cmd", right-click on it, and select "Run as administrator".

##### 2. Run the Installation Command:

  * Execute the following command:

```cmd
@"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -InputFormat None -ExecutionPolicy Bypass -Command " [System.Net.ServicePointManager]::SecurityProtocol = 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))" && SET "PATH=%PATH%;%ALLUSERSPROFILE%\chocolatey\bin"
```
##### 3. Verify Installation:

  * After installation, close and reopen CMD, then run:

```cmd
choco -v
```

  * This should display the installed version of Chocolatey.

### 📦 Using Chocolatey
Once installed, you can use Chocolatey to manage software packages:

#####   - Install a Package:

```cmd
choco install [package-name] -y
```
Replace [package-name] with the desired software name. For example:

```cmd
choco install git -y
```
#####   - Upgrade a Package:

```cmd
choco upgrade [package-name] -y
```
#####   - Uninstall a Package:

```cmd
choco uninstall [package-name] -y
```
#####   - Search for Packages:

```cmd
choco search [keyword]
```
#####   - List Installed Packages:

```cmd
choco list --local-only
```
You can explore available packages at the Chocolatey Community Repository.

### 🧩 Additional Features
#### 1. Custom Repositories: Chocolatey allows the addition of custom or internal repositories for package management.

#### 2. Integration with Configuration Management Tools: Chocolatey can be integrated with tools like Puppet, Ansible, and Chef for automated deployments.

#### 3. Graphical User Interface (GUI): For users preferring a GUI, install Chocolatey GUI:

```cmd
choco install chocolateygui -y
```
