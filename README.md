# Get-FTPList

Outputs a list of files from an FTP server as PowerShell objects.

This PowerShell script connects to an FTP server and outputs a list of files or directories in the specified directory as PowerShell objects. You can use these objects to perform various operations, such as sorting, filtering, summing up file sizes, etc. The script also supports recursive listing mode, which allows you to list files or directories in subdirectories up to a specified depth.

## Prerequisites

To run this script, you need:

- PowerShell 5.1 or higher
- A valid FTP server URL, port, user name, and password
- A directory on the FTP server to list files or directories from


## Usage

To run this script, you can use the following command:

```powershell
.\Get-FTPList.ps1 -Url <ftp_url> -Port <ftp_port> -User <ftp_user> -Pass <ftp_pass> -Directory <ftp_directory> [-Recurse] [-Depth <depth>]
```

The parameters are:

- -Url: The URL of the FTP server, such as ftp://example.com.
- -Port: The port number of the FTP server, such as 21. The default value is 21.
- -User: The user name for the FTP server, such as anonymous.
- -Pass: The password for the FTP server, such as anonymous@example.com.
- -Directory: The directory on the FTP server to list files or directories from, such as /pub. The default value is /.
- -Recurse: A switch parameter that indicates whether to list files or directories in subdirectories recursively. The default value is $false.
- -Depth: An integer parameter that indicates the maximum depth of subdirectories to list files or directories from. The default value is 1.

The output of the script is a list of PowerShell objects, each of which has the following properties:

- Directory: The directory on the FTP server where the file or directory is located.
- Name: The name of the file or directory.
- Length: The size of the file or directory in bytes.
- Date: The date and time of the last modification of the file or directory.
- Mode: The mode of access of the file or directory, such as -rw-r--r--.
- Owner: The owner of the file or directory, such as root.
- Group: The group of the file or directory, such as root.
- Url: The full URL of the file or directory on the FTP server.
- IsContainer: A boolean value that indicates whether the entry is a directory.

You can use these objects to perform various operations, such as sorting, filtering, summing up file sizes, etc. For example, you can use the following command to sort the output by size in descending order:

```powershell
.\Get-FTPList.ps1 -Url ftp://example.com -User anonymous -Pass anonymous@example.com -Directory /pub | Sort-Object -Property Length -Descending
```

## Features
This script has the following features:

- It uses the dotnet TcpClient function to communicate with the FTP server. It does not use any web requests or installed programs, modules, or classes.
- It determines the supported commands and options of the FTP server at the start of the script.
- It *always* switches to passive mode FTP.
- ~It reliably and confidently determines the type of server used (Windows, FreeBSD, Linux, etc.) and correctly parses the output of any of them.~

## License
This script is licensed under the MIT License. See the LICENSE file for more details.

## Author
This script was written by Le Berouque. You can contact me at berouque@outlook.com or visit [my github profile](https://github.com/berouques) for more projects.
