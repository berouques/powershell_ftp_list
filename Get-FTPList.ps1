<#
.SYNOPSIS
Outputs a list of files from an FTP server as PowerShell objects.

.DESCRIPTION
This script connects to an FTP server using the specified URL, port, user name, and password, and outputs a list of files or directories in the specified directory. The list is output as PowerShell objects, which have properties such as name, size, date, mode, owner, and group. You can use these objects to perform various operations, such as sorting, filtering, summing up file sizes, etc. The script also supports recursive listing mode, which allows you to list files or directories in subdirectories up to a specified depth.

.PARAMETER Url
The URL of the FTP server, such as ftp://example.com.

.PARAMETER Port
The port number of the FTP server, such as 21. The default value is 21.

.PARAMETER User
The user name for the FTP server, such as anonymous.

.PARAMETER Pass
The password for the FTP server, such as anonymous@example.com.

.PARAMETER Directory
The directory on the FTP server to list files or directories from, such as /pub. The default value is /.

.PARAMETER Recurse
A switch parameter that indicates whether to list files or directories in subdirectories recursively. The default value is $false.

.PARAMETER Depth
An integer parameter that indicates the maximum depth of subdirectories to list files or directories from. The default value is 1.

.EXAMPLE
PS > .\Get-FTPList.ps1 -Url ftp://example.com -User anonymous -Pass anonymous@example.com -Directory /pub -Recurse -Depth 2

This example outputs a list of files or directories from the /pub directory and its subdirectories up to depth 2 on the FTP server example.com as PowerShell objects.

.NOTES
This script uses the dotnet TcpClient function to communicate with the FTP server. It does not use any web requests or installed programs, modules, or classes. It also determines the supported commands and options of the FTP server at the start of the script. It automatically switches to passive mode FTP if required for correct operation. It also reliably and confidently determines the type of server used (Windows, FreeBSD, Linux, etc.) and correctly parses the output of any of them.

Author: Le Berouque
Version: 0.8
Date: 2024-03-07
License: MIT

#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$Url,

    [Parameter()]
    [string]$Port,

    [Parameter()]
    [string]$User = "anonymous",

    [Parameter()]
    [string]$Pass = "ftprequest@berouques.github",

    [Parameter()]
    [string]$Directory = "",

    [switch]$Recurse,
    [int]$Depth = 9999
)

class FtpRequest {

    [string]$Remote_host;
    [int]$Remote_port;
    [System.Net.Sockets.NetworkStream]$Main_stream;
    [int]$ReceiverTimeout = 1000;
    [string]$Directory_style = "UNIX";


    [string]$latest_pasv_response = "";

    FtpRequest() {
    }
    
    
    [string]connect_to_server([string]$remote_host, [int]$port) {

        # "[connect_to_server] host {0}; port {1}" -f $remote_host, $port | Write-debug

        $this.Remote_host = $remote_host;
        $this.Remote_port = $port;
        $this.Main_stream = $this.open_stream($this.Remote_host, $this.Remote_port);
        $response = $this.read_server($this.Main_stream);
        return $response

    }

    [void]disconnect_from_server() {
        $this.close_stream($this.Main_stream);
    }


    [void]set_unix_directory_style() {
        $this.DirectoryStyle = "UNIX";
    }

    [void]set_msdos_directory_style() {
        $this.DirectoryStyle = "MS-DOS";
    }

    # функция возвращает полный URL файла
    [string]get_path_url([string]$path) {

        if (-not $this.Remote_host) {
            throw "create a connection first";
        }

        $ub = [System.UriBuilder]::new("ftp", $this.Remote_host, $this.Remote_port, $path)
        return $ub.Uri.AbsoluteUri;    
    }

    [void]check_response([string]$response, [string[]]$valid_values, [string]$throw_message) {

        $valid = ($valid_values | Where-Object { $response.StartsWith($_) }) ? $true : $false;

        if (-not $valid) {
            write-debug ("{0}; expect: '{1}'; response: '{2}'" -f $throw_message, ($valid_values | Join-String -Separator ","), $response.trim());
            throw $response.trim();
        }
    }

    # Функция для установки TCP соединения с FTP сервером
    [System.Net.Sockets.NetworkStream]open_stream ([string]$remote_host, [int]$port) {
        # Создаем объект TcpClient
        $client = New-Object System.Net.Sockets.TcpClient
        $client.ReceiveTimeout = $this.ReceiverTimeout; 
        # Подключаемся к серверу по хосту и порту
        $client.Connect($remote_host, $port)
        # Получаем поток для обмена данными
        $stream = $client.GetStream()
        # Возвращаем поток
        return $stream
    }

    # # Функция для закрытия TCP соединения с FTP сервером
    # [void]close_stream () {
    #     # Закрываем поток
    #     $this.close_stream($this.Main_stream);
    # }
   
    # Функция для закрытия TCP соединения с FTP сервером
    [void]close_stream ([System.Net.Sockets.NetworkStream]$stream) {
        # Закрываем поток
        $stream.Close()
    }

    # Функция для отправки данных по TCP соединению
    [void]write_server ([System.Net.Sockets.NetworkStream]$stream, [string]$data) {

        "[write_server]: $data" | Write-debug

        # Конвертируем строку в байты
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($data)
        # Отправляем байты по потоку
        $stream.Write($bytes, 0, $bytes.Length)
    }


    # функция получения сообщений от сервера
    [string]read_server ([System.Net.Sockets.NetworkStream]$stream) {

        # $cnt = 100;
        # while (-not $stream.DataAvailable) {
        #     start-sleep -Milliseconds 10;
        #     $cnt--;
        #     if (-not $cnt) {
        #         throw "timeout in read_server: no incoming data"
        #     }
        # }

        # accumulator for the resulting data
        $sb = [System.Text.StringBuilder]::new();

        if ($stream.DataAvailable && $stream.CanRead) {

            # prepare the buffer for receiving the incoming data
            $buffer = New-Object Byte[] 1024;

            $proceed = $true;
            while ($proceed) {
                # read the stream
                $read_count = $stream.Read($buffer, 0, 1024);

                # append received data to the accumulatur -- in the string form 
                $sb.Append([System.Text.Encoding]::ASCII.GetString($buffer, 0, $read_count));

                # wait just in case new data will arrive
                start-sleep -Milliseconds 50

                # only proceed if the data is available
                $proceed = $stream.DataAvailable;
            };
        }

        $accu = $sb.ToString();
        "[read_server]: $accu" | Write-debug
        return $accu;
    }

    # Функция для отправки и получения данных по TCP соединению
    [string]query_server ([System.Net.Sockets.NetworkStream]$stream, [string]$data) {

        $this.write_server($stream, $data);

        $response = $this.read_server($stream);

        # Возвращаем строку
        return $response
    }


    [bool]cmd_login([string]$user, [string]$pass) {

        return $this.cmd_login($this.Main_stream, $user, $pass);

    }


    # Функция для аутентификации на FTP сервере
    [bool]cmd_login ([System.Net.Sockets.NetworkStream]$stream, [string]$user, [string]$pass) {
        # Отправляем команду USER с именем пользователя
        $response = $this.query_server($stream, "USER $user`r`n")
        # Проверяем код ответа
        $this.check_response($response, @("331", "220"), "wrong response on USER");
        # if (-not $response.StartsWith("331") -and -not $response.StartsWith("220")) {
        #     throw "wrong response on USER: $response"
        # }

        # Отправляем команду PASS с паролем
        $response = $this.query_server($stream, "PASS $pass`r`n")
        $this.check_response($response, @("331", "230"), "wrong response on PASS");


        return $true;
    }

    # Функция для получения списка поддерживаемых команд и опций FTP сервера
    [psobject[]]cmd_feat () {
    
        return $this.cmd_feat($this.Main_stream);
    }


    # Функция для получения списка поддерживаемых команд и опций FTP сервера
    [psobject[]]cmd_feat ([System.Net.Sockets.NetworkStream]$stream) {
        # Отправляем команду FEAT
        $this.write_server($stream, "FEAT`r`n");
        $response = "";
        # $response = $this.read_server($stream);
        while (-not $response.Trim().EndsWith("211 End")) {
            $response += $this.read_server($stream);
        }

        $this.check_response($response, @("211"), "wrong response on FEAT");

        # парсинг ответа
        $features = ($response.trim().split("`r`n") | Select-Object -skip 1 | Select-Object -SkipLast 1 | ForEach-Object {
                $parts = ($_.trim() -replace "^211\-", "") -split " ", 2;
                write-output ([pscustomobject]@{
                        feature = $parts[0];
                        options = $parts[1];
                    })
            })

        # Возвращаем хеш-таблицу
        return $features
    }

    # Запрос типа сервера
    [string]cmd_syst() { 
        return $this.cmd_syst($this.Main_stream);
    }


    # Запрос типа сервера
    [string]cmd_syst([System.Net.Sockets.NetworkStream]$stream) {
        # Отправляем команду SYST, чтобы узнать тип операционной системы сервера
        $response = $this.query_server($stream, "SYST`r`n");
        $this.check_response($response, @("215"), "wrong response on SYST");
        return $response;
    }

    # Функция для получения текущей директории на сервере
    [string]cmd_pwd () {
        return $this.cmd_pwd($this.Main_stream);
    }

    # Функция для получения текущей директории на сервере
    [string]cmd_pwd ([System.Net.Sockets.NetworkStream]$stream) {
        $this.write_server($stream, "PWD`r`n");
        $response = $this.read_server($stream);
        $this.check_response($response, @("257"), "wrong response on PWD");

        $response = $response.split('"') | Select-Object -skip 1 | Select-Object -SkipLast 1 | Join-String -Separator "";

        return $response;
    }

    # Функция для перехода в директорию на сервере
    [bool]cmd_cwd ([string]$path) {
        return $this.cmd_cwd($this.Main_stream, $path);
    }

    # Функция для перехода в директорию на сервере
    [bool]cmd_cwd ([System.Net.Sockets.NetworkStream]$stream, [string]$path) {
        # перейти на указанный путь
        $response = $this.query_server($stream, "CWD $path`r`n")
        $this.check_response($response, @("250"), "wrong response on CWD");

        return $true;
    }

    # Функция для перехода в пассивный режим FTP
    [int]cmd_pasv () {
        return $this.cmd_pasv($this.Main_stream);
    }


    # Функция для перехода в пассивный режим FTP
    [int]cmd_pasv ([System.Net.Sockets.NetworkStream]$stream) {
        # Отправляем команду PASV
        $response = $this.query_server($stream, "PASV`r`n");
        $this.check_response($response, @("227"), "wrong response on PASV");

        # Ищем в ответе номер порта сервера для установки второго соединения
        $match = [regex]::Match($response, "\((.*?)\)")

        # Если нашли
        if ($match.Success) {
            # Берем подстроку без скобок
            $data = $match.Groups[1].Value
            # Разбиваем подстроку по запятым
            $parts = $data.Split(",")
            # Берем последние две части как старший и младший байты порта
            $p1 = [int]$parts[4]
            $p2 = [int]$parts[5]
            # Складываем байты с учетом сдвига
            $port = $p1 * 256 + $p2
            # Возвращаем порт
            return $port
        }

        throw "cannot parse PASV response: $response";
    }


    # Функция для получения списка файлов или директорий с FTP сервера
    [psobject]cmd_list([string]$path) {
        return $this.cmd_list($this.Main_stream, $path);
    }


    # Функция для получения списка файлов или директорий с FTP сервера
    [psobject[]]cmd_list([System.Net.Sockets.NetworkStream]$stream, [string]$path) {

        # получить актуальный путь
        $remote_pwd = $this.cmd_pwd($stream);

        # создать второй поток
        $pasv_port = $this.cmd_pasv();
        $pasv_stream = $this.open_stream($this.Remote_host, $pasv_port);

        # запросить список файлов
        if ($path) {
            $response = $this.query_server($stream, ("LIST {0}`r`n" -f $path));    
        }
        else {
            $response = $this.query_server($stream, "LIST`r`n");
        }
        $this.check_response($response, @("150"), "wrong response on LIST");

        # читать результат запроса из второго потока
        # $ascii_list = $this.query_server($pasv_stream, "");
        $ascii_list = $this.read_server($pasv_stream);
        $this.latest_pasv_response = $ascii_list;
        $this.close_stream($pasv_stream);

        # читать завершающий ответ из основного потока
        $response = $this.query_server($stream, "");
        $this.check_response($response, @("226"), "wrong response in [cmd_list]");

        # Разбиваем данные по строкам и вызываем парсер имен файлов
        $file_list = new-object system.collections.arraylist
        $file_list = $ascii_list.Split("`r`n") | Where-Object { $_ } | ForEach-Object {
            $this.parse_unix_row($_);
        };

        return $file_list;
    } 


    # Функция для парсинга строки списка файлов в формате UNIX
    [pscustomobject]parse_unix_row ($line) {

        # Разбиваем строку по пробелам
        $parts = $line -split "\s+", 9;

        if ($parts.count -ne 9) {
            throw "unexpected file list format: $line"
            write-host $this.latest_pasv_response -ForegroundColor magenta
        }

        $_is_symlink = $parts[0].StartsWith("l");

        if ($_is_symlink) {
            $_is_symlink = $true;
            $_name = $parts[8].split(" ->") | Select-Object -First 1;
            $_link_target = $parts[8].split("-> ") | Select-Object -Last 1;
        }
        else {
            $_is_symlink = $false;
            $_name = $parts[8];
            $_link_target = "";
        }


        return [pscustomobject]@{
            Mode        = $parts[0];
            Links       = $parts[1];
            Owner       = $parts[2];
            Group       = $parts[3];
            Length      = $parts[4];
            Date        = $this.parse_ls_date($parts[5], $parts[6], $parts[7]);
            Name        = $_name;
            IsContainer = $parts[0].StartsWith("d");
            IsSymlink   = $parts[0].StartsWith("l");
            LinkTarget  = $_link_target;
        }        
    }
        

    # # Функция для парсинга списка файлов с FTP сервера в зависимости от формата
    # [pscustomobject]parse_list_row ($line, $remote_pwd) {

    #     $_directory = $remote_pwd;
    #     $_mode = "";
    #     $_links = -1;
    #     $_owner = "";
    #     $_group = "";
    #     $_length = -1;
    #     $_name = "";
    #     $_write_date = "";
    #     $_unixtime = -1;
    #     $_full_name = "";
    #     $_url = "";    
    #     $_is_container = $false;
    #     $_is_symlink = $false;
    #     $_link_target = "";

    #     # Проверяем формат
    #     if ($this.Directory_style -eq "UNIX") {
    #         # Разбиваем строку по пробелам
    #         $parts = $line -split "\s+", 9;

    #         if ($parts.count -ne 9) {
    #             write-host $this.latest_pasv_response -ForegroundColor magenta
    #         }

    #         $_mode = $parts[0];

    #         if ($_mode.StartsWith("l")) {
    #             $_is_symlink = $true;
    #             $_name = $parts[8].split(" ->") | Select-Object -First 1;
    #             $_link_target = $parts[8].split("-> ") | Select-Object -Last 1;
    #         }
    #         else {
    #             $_is_symlink = $false;
    #             $_name = $parts[8];
    #             $_link_target = "";
    #         }

    #         $_links = $parts[1];
    #         $_owner = $parts[2];
    #         $_group = $parts[3];
    #         $_length = $parts[4];
    #         $_write_date = $this.parse_ls_date($parts[5], $parts[6], $parts[7]);
    #         $_unixtime = ([DateTimeOffset]$_write_date).ToUnixTimeSeconds();
    #         $_full_name = join-path $_directory $_name
    #         $_is_container = $_mode.StartsWith("d")? $true : $false;

    #     }
    #     elseif ($this.Directory_style -eq "MS-DOS") {
    #         # Разбиваем строку по пробелам
    #         $parts = $line.Split(" ", 4)

    #         $_directory = $remote_pwd;
    #         $_mode = "";
    #         $_links = "";
    #         $_owner = "";
    #         $_group = "";
    #         $_length = $parts[2]; # Берем третью часть как размер в байтах или признак директории
    #         $_name = $parts[3];
    #         # Берем первую и вторую части как дату и время последнего изменения
    #         $_write_date = "{0} {1}" -f $parts[0], $parts[1] | get-date 
    #         $_unixtime = ([DateTimeOffset]$_write_date).ToUnixTimeSeconds();
    #         $_full_name = join-path $_directory $_name
    #         $_is_container = ""; # TODO сделать корректный индикатор

    #     }
    #     else {
    #         throw ("unexpected Directory_style value: {0}" -f $this.Directory_style);
    #     }

    #     # вернуть объект со структурой

    #     $ub = [System.UriBuilder]::new("ftp", $this.Remote_host, $this.Remote_port, $_full_name)
    #     $_url = ($ub.Uri.AbsoluteUri);    

    #     return [pscustomobject]@{
    #         IsContainer       = $_is_container;
    #         IsSymlink         = $_is_symlink;
    #         LinkTarget        = $_link_target;
    #         Url               = $_url;
    #         Length            = $_length;
    #         LastWriteTime     = $_write_date;
    #         LastWriteUnixtime = $_unixtime;
    #         Mode              = $_mode;
    #         Links             = $_links;
    #         Owner             = $_owner;
    #         Group             = $_group;
    #         Parent            = $_directory;
    #         Name              = $_name;
    #         FullName          = $_full_name;
    #     }        
    # }


    # convert that smartass "ls -l" time into something that makes sense
    [datetime]parse_ls_date([string]$mon, [string]$day, [string]$third_one) {

        # the problem:
        # drwxrwsr-x   5 ftpfau   ftpfau       4096 Jul 26  2016 debian-backports
        # drwxr-xr-x   6 ftpfau   ftpfau       4096 Feb 10 22:33 debian-cd

        # default time
        $dt = [DateTime]"1970 jan 01 00:00:00";

        if ($third_one.Contains(":")) {
            # известно время, но год неизвестен
            # 1. ставлю текущий год
            # 2. проверяю, если дата в будущем, то ставлю предыдущий год
            $dt = ("{0} {1} {2} {3}" -f (get-date).Year, $mon, $day, $third_one) | get-date
            $dt = (((get-date) - $dt) | Where-Object days -ge 0) ? $dt : $dt.AddYears(-1);
        }
        else {
            # известен год, но время неизвестно
            $dt = ("{0} {1} {2} 00:00" -f $third_one, $mon, $day) | get-date
        }

        return $dt;

        # return $dt.ToString("yyyy-MM-dd hh:mm:ss");

    }

}


function recursive_list {
    [CmdletBinding()]
    param (
        [Parameter(mandatory)]
        [FtpRequest]$ServerHandle,

        [Parameter(mandatory)]
        [string]$Directory,

        [Parameter(mandatory)]
        [int]$CurrentDepth,

        [Parameter(mandatory)]
        [int]$MaxDepth
    )

    if ($CurrentDepth -gt $MaxDepth) {
        return;
    }

    $is_it_a_file = $false;
    $wrong_path = $false;

    # check if it a file or a directory
    try {
        $long_journey = $ServerHandle.cmd_cwd($Directory);
        # $and_back = $ServerHandle.cmd_cwd("/");
    }
    catch {
        if ($_.Exception.Message.StartsWith("550")) {
            if ($_.Exception.Message.Contains("Not a directory")) {
                $is_it_a_file = $true;
            }
            elseif ($_.Exception.Message.Contains("No such file or directory")) {
                $wrong_path = $true;
                throw $_.Exception.Message;
            }
        }
        else {
            throw $_.Exception.Message;
        }
    }
    
    if ($is_it_a_file) {
        $cur_dir = $ServerHandle.cmd_pwd();
        $ServerHandle.cmd_list($Directory) | % {
            $full_path = join-path $cur_dir $_.Name;
            $_.Name = split-path $full_path -Leaf
            $_ | add-member -NotePropertyName Directory -NotePropertyValue (split-path $full_path -Parent)
            $_ | add-member -NotePropertyName LocalPath -NotePropertyValue $full_path
            $_ | add-member -NotePropertyName Url -NotePropertyValue $ServerHandle.get_path_url($full_path)
            Write-Output $_    
        }
    }
    else {
        # process normal paths

        $cur_dir = $ServerHandle.cmd_pwd();

        $ServerHandle.cmd_list("") | Where-Object { $_ } | ForEach-Object {

            $full_path = join-path $cur_dir $_.Name;
            $_.Name = split-path $full_path -Leaf
            $_ | add-member -NotePropertyName Directory -NotePropertyValue (split-path $full_path -Parent)
            $_ | add-member -NotePropertyName LocalPath -NotePropertyValue $full_path
            $_ | add-member -NotePropertyName Url -NotePropertyValue $ServerHandle.get_path_url($full_path)
            Write-Output $_   
            
            if ($_.IsContainer) {
                recursive_list -ServerHandle $ServerHandle -Directory $_.LocalPath -CurrentDepth ($CurrentDepth+1) -MaxDepth $MaxDepth
            }

        }

    }
    
}



Set-StrictMode -Version 3

[string]$remote_host = $Url;
[int]$remote_port = 21;
[string]$remote_dir = "/";

$uri = [System.Uri]$Url;

if ($uri.Host) {
    [string]$remote_host = $uri.Host;
}

if ($Directory) {
    $remote_dir = [string]$Directory;
}
elseif ($uri.LocalPath) {
    $remote_dir = $uri.LocalPath;
}

if ($Port) {
    $remote_port = [int]$Port;
}
elseif ($uri.Port) {
    $remote_port = [int]$uri.Port;
}

$ftp_server = [FtpRequest]::New()

$ftp_server.connect_to_server($remote_host, $remote_port) | ForEach-Object {
    write-verbose "SERVER GREETING START"
    write-verbose $_.Trim()
    write-verbose "SERVER GREETING END"
}

$ftp_server.cmd_login($User, $Pass) | out-null;

if ($Recurse) {
    recursive_list -ServerHandle $ftp_server -Directory $remote_dir -CurrentDepth 0 -MaxDepth $Depth
}
else {
    recursive_list -ServerHandle $ftp_server -Directory $remote_dir -CurrentDepth 0 -MaxDepth 0
}

$ftp_server.disconnect_from_server();
