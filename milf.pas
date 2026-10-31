program MILF;

uses atari, crt;

const

     { SIO direction }

     SIO_READ        = $40;
     SIO_WRITE       = $80;

     { SIO commands }

     FORMAT_DISK              = $21;
     FORMAT_SINGLE            = $21;
     FORMAT_ENHANCED          = $22;
     READ_PERCOM              = $4e;
     WRITE_PERCOM             = $4f;
     PUT_SECTOR               = $50;
     PUT_SECTOR_WITH_VERIFY   = $57;
     READ_SECTOR              = $52;
     READ_STATUS              = $53;

     { SIO status codes }

     SIO_OK                   = 1;
     SIO_TIMEOUT              = 138;
     SIO_NAK                  = 139;

     { Used memory locations }

     PERCOM_BUFFER_MEM     = $600;
     PERCOM_BUFFER_MEM_OLD = $620;

     COPY_BUFFER_MEM     = $6000;
     LOG_BUFFER          = $6200;

     { Log constants }

     LOG_READ_ERROR      = 114;
     LOG_READ_SUCCESS    = 111;
     LOG_WRITE_ERROR     = 119;
     LOG_RECORD_SIZE     = 7;
     LOG_MAX_RECORDS     = 2880;
     EOL                 = $9b;

     { Fast copy: sectors held in memory between the read and write pass }

     MAX_BATCH_SECTORS   = 256;

     { copyError results }

     ACTION_ABORT        = 1;
     ACTION_RETRY        = 2;
     ACTION_SKIP         = 3;
     ACTION_WRITE_BUFFER = 4;

     { Percom blocks: SS SD, SS ED, SS DD, DS DD, DS QD }

     PERCOM_CONFIGS      : array[0..59] of byte = (
                              40,2,0,18,0,0,0,128,0,0,0,0,
                              40,2,0,26,0,4,0,128,0,0,0,0,
                              40,2,0,18,0,4,1,  0,0,0,0,0,
                              40,2,0,18,1,4,1,  0,0,0,0,0,
                              80,2,0,18,1,4,1,  0,0,0,0,0);


var

     { SIO device control block }

     DDEVIC                        : byte absolute $0300;
     DUNIT                         : byte absolute $0301;
     DCOMND                        : byte absolute $0302;
     DSTATS                        : byte absolute $0303;
     DBUF                          : word absolute $0304;
     DTIMLO                        : byte absolute $0306;
     DBYT                          : word absolute $0308;
     DAUX                          : word absolute $030a;

     percomBlock                   : array[0..11] of byte absolute PERCOM_BUFFER_MEM;
     CH                            : byte absolute $02fc;
     MEMTOP                        : word absolute $02e5;
     SIOresult                     : byte;
     CIOresult                     : byte;
     tmpBool                       : boolean;
     tmpByte                       : byte;
     tmpWord                       : word;
     tmpString                     : string[17];
     key                           : char;
     f                             : file;
     Code                          : byte;

     matchSuccess                  : boolean;
     oldPercomValid                : boolean;

     source_drive                  : byte;
     dest_drive                    : byte;
     source_drive_not_configurable : boolean;
     dest_drive_not_configurable   : boolean;

     bytes_per_sector_source       : word;
     bytes_per_sector_dest         : word;
     sectors_source                : word;
     sectors_dest                  : word;
     bytes_per_sector              : word;
     number_of_sectors             : word;

     current_sector                : word;
     sector_index                  : word;
     sectors_to_read               : word;
     start_sector                  : integer;
     end_sector                    : integer;
     operations_number             : word;
     log_is_truncated              : boolean;
     log_capacity                  : word;

     sectors_succesfully_read      : word;
     progressLabel                 : string[28];
     progressShown                 : boolean;
     skipSector                    : array[0..MAX_BATCH_SECTORS - 1] of boolean;

     autoAction                    : byte;
     maxRetries                    : integer;
     opMaxRetries                  : integer;
     verify                        : boolean;
     createLog                     : boolean;
     logging                       : boolean;

procedure getString(maxChars: byte);
begin
     asm {

          iccmd    = $0342
          icbufa   = $0344
          icbufl   = $0348

          txa:pha

          lda #<COPY_BUFFER_MEM
          ldy #>COPY_BUFFER_MEM
          ldx #$00
          sta icbufa,x
          tya
          sta icbufa+1,x
          lda maxChars
          sta icbufl,x
          lda #$00
          sta icbufl+1,x
          lda #$05
          sta iccmd,x
          jsr $E456
          pla:tax

          sty CIOresult

     };
end;


procedure exec_sio(sunit: byte; command: byte; direction: byte; timeout: byte; buffer: word; size: word; aux: word);
begin
     DDEVIC := $31;
     DUNIT  := sunit;
     DCOMND := command;
     DSTATS := direction;
     DBUF   := buffer;
     DTIMLO := timeout;
     DBYT   := size;
     DAUX   := aux;

     asm {
          txa:pha
          jsr  $E459
          pla:tax

          sty  SIOresult
     };

end;



procedure exitToDOS;
begin
     asm {
          jmp ($a)
          rts
     };
end;



procedure coldStart;
begin
     asm {
          jmp $e477;
          rts
     };
end;



function breakPressed:boolean;
begin
     Result := CIOresult = 128;
end;



procedure clearKeys;
begin
     CH := $ff; key := #0;
end;



{ Waits for one of the allowed keys (upper case letters, digits, #27) }
function WaitKey(const allowed: string): char;
var
     i: byte;
begin

     clearKeys;

     repeat
          repeat until keypressed;
          Result := UpCase(ReadKey);
          for i := 1 to Length(allowed) do
               if Result = allowed[i] then exit;
     until false;

end;



procedure pressKey;
begin

     clearKeys;
     Delay(2);

     Writeln;
     Writeln('Press key...');
     Writeln;
     repeat until keypressed;

end;



procedure clearLogBuffer;
begin
     fillbyte(pointer(LOG_BUFFER), log_capacity * LOG_RECORD_SIZE, 0);
end;



procedure clearPercomBuffer;
begin
     fillbyte(pointer(PERCOM_BUFFER_MEM), 14, 0);
end;



{ Reads a line from the editor into tmpString, at most maxChars - 1 characters }
procedure readLine(maxChars: byte);
var
     len: byte;
begin

     getString(maxChars);

     len := 0;
     while (len < maxChars - 1) and (Peek(COPY_BUFFER_MEM + len) <> EOL) do inc(len);

     SetLength(tmpString, len);
     Move(pointer(COPY_BUFFER_MEM), tmpString[1], len);

end;



{ Sets number_of_sectors and bytes_per_sector from percomBlock }
procedure decodePercom;
begin
     number_of_sectors := percomBlock[0] * (percomBlock[2] * $100 + percomBlock[3]);
     number_of_sectors := number_of_sectors * (percomBlock[4] + 1);
     bytes_per_sector := percomBlock[6] * $100 + percomBlock[7];
end;



procedure readPercom(drive: byte; silent: boolean; sourceOrDestination: char);
var
     configurable: boolean;
begin

     number_of_sectors := 0;
     bytes_per_sector := 0;
     configurable := false;

     clearPercomBuffer;

     exec_sio(drive, READ_STATUS, SIO_READ, 7, PERCOM_BUFFER_MEM, 4, 0);
     exec_sio(drive, READ_PERCOM, SIO_READ, 7, PERCOM_BUFFER_MEM, 12, 0);

     if SIOresult = SIO_NAK then begin

          if not silent then begin
               Writeln('Drive does not support PERCOM.');
               Writeln('Probably Atari 810 or Atari 1050.');
               Writeln('Trying to detect density...');
          end;
          exec_sio(drive, READ_SECTOR, SIO_READ, $7, PERCOM_BUFFER_MEM, 128, 721);
          if SIOresult = SIO_OK then
               number_of_sectors := 1040
          else
               number_of_sectors := 720;
          bytes_per_sector := 128;
          SIOresult := SIO_OK;

     end else if SIOresult = SIO_TIMEOUT then begin

          Writeln('Drive does not respond.');

     end else if SIOresult > 127 then begin

          Writeln('Drive error ', SIOresult, '.');

     end else begin

          decodePercom;
          configurable := true;

     end;

     if sourceOrDestination = 's' then begin
          bytes_per_sector_source := bytes_per_sector;
          sectors_source := number_of_sectors;
          source_drive_not_configurable := not configurable;
     end else begin
          bytes_per_sector_dest := bytes_per_sector;
          sectors_dest := number_of_sectors;
          dest_drive_not_configurable := not configurable;
     end;

     if (not silent) and (bytes_per_sector > 0) then
          writeln (number_of_sectors, ' sectors of ', bytes_per_sector, ' bytes.');

end;



procedure errorMessage(err: byte);
begin
     write('Status: ');
     if err > $7f then begin
          writeln('error ', err);
     end else writeln('OK');
end;



procedure writeMenu;
begin

     writeln;

     writeln ('Current source drive: D', source_drive);
     readPercom(source_drive, false, 's');
     Writeln ('-------------------------------------');
     writeln ('Current destination drive: D', dest_drive);
     readPercom(dest_drive, false, 'd');

     writeln;
     writeln ('R'*' - Read drive configuration');
     writeln ('W'*' - Write drive configuration');
     writeln ('F'*' - Format drive');
     writeln ('D'*' - Set source, destination drives');
     writeln ('X'*' - Exchange source and destination');
     writeln ('C'*' - Copy sectors');
     writeln ('M'*' - Fast copy (memory buffer)');
     writeln ('O'*' - Set options');
     writeln;
     writeln ('Q'*' - Exit to DOS');
     writeln ('B'*' - Cold start');
     writeln;

end;



procedure swapDrives;
begin

     tmpByte := source_drive;
     source_drive := dest_drive;
     dest_drive := tmpByte;

     tmpBool := source_drive_not_configurable;
     source_drive_not_configurable := dest_drive_not_configurable;
     dest_drive_not_configurable := tmpBool;

     tmpWord := bytes_per_sector_source;
     bytes_per_sector_source := bytes_per_sector_dest;
     bytes_per_sector_dest := tmpWord;

     tmpWord := sectors_source;
     sectors_source := sectors_dest;
     sectors_dest := tmpWord;

     Writeln ('Drive were swapped.');

     pressKey;

     writeMenu;

end;



label exitFormat;
procedure format;
var
     drive: byte;
     sector_size: word;
     notConfigurable: boolean;
begin

     Writeln ('S - Source drive');
     Writeln ('D - Destination drive');

     case WaitKey('SD'#27) of
          'S': begin drive := source_drive; sector_size := bytes_per_sector_source; notConfigurable := source_drive_not_configurable end;
          'D': begin drive := dest_drive; sector_size := bytes_per_sector_dest; notConfigurable := dest_drive_not_configurable end;
          else goto exitFormat;
     end;

     Writeln;
     Writeln('All data on D', drive, ' will be lost.');
     Writeln('Continue? (Y/N)');

     if WaitKey('YN'#27) <> 'Y' then goto exitFormat;

     if notConfigurable then begin

          Writeln;
          Writeln('This drive is not configurable');
          Writeln('Only ','S'*' - 90 KB, ','E'*' - 130 KB');
          Writeln('densities are available.');

          case WaitKey('SE'#27) of
               'S': begin writeln; writeln('Formatting disk.'); exec_sio(drive, FORMAT_SINGLE, SIO_READ, $40, COPY_BUFFER_MEM, 128, 1); end;
               'E': begin writeln; writeln('Formatting disk.'); exec_sio(drive, FORMAT_ENHANCED, SIO_READ, $40, COPY_BUFFER_MEM, 128, 1); end;
               else goto exitFormat;
          end;

     end else begin
          writeln;
          writeln('Formatting disk.');
          exec_sio(drive, FORMAT_DISK, SIO_READ, $40, COPY_BUFFER_MEM, sector_size, 1);
     end;

     errorMessage(SIOresult);

     exitFormat:

     pressKey;

     writeMenu;
end;



procedure matchDrives;
begin

     matchSuccess := false;

     Writeln;

     exec_sio(dest_drive, READ_PERCOM, SIO_READ, 7, PERCOM_BUFFER_MEM_OLD, 12, 0);
     oldPercomValid := SIOresult = SIO_OK;

     Writeln ('Reading source configuration.');
     exec_sio(source_drive, READ_STATUS, SIO_READ, 7, PERCOM_BUFFER_MEM, 4, 0);
     exec_sio(source_drive, READ_PERCOM, SIO_READ, 7, PERCOM_BUFFER_MEM, 12, 0);
     if SIOresult > 127 then begin
          errorMessage(SIOresult);
          exit;
     end;
     Writeln ('Configuring destination drive.');
     exec_sio(dest_drive, WRITE_PERCOM, SIO_WRITE, 7, PERCOM_BUFFER_MEM, 12, 0);
     if SIOresult > 127 then begin
          errorMessage(SIOresult);
          exit;
     end;
     Writeln ('Formatting destination drive.');
     exec_sio(dest_drive, FORMAT_DISK, SIO_READ, $40, COPY_BUFFER_MEM, bytes_per_sector_source, 1);
     if SIOresult > 127 then begin
          errorMessage(SIOresult);
          exit;
     end;

     readPercom(dest_drive, true, 'd');
     if (bytes_per_sector_dest <> bytes_per_sector_source) or (sectors_dest <> sectors_source) then begin
          Writeln ('Destination drive did not accept');
          Writeln ('source configuration.');
          exit;
     end;

     Writeln ('Formatting finished');

     matchSuccess := true;

end;



procedure changeDrives;
const
     tmpArr  : array[0..1] of string[11] = ('source', 'destination');
     tmpArr2 : array[0..1] of char = ('s', 'd');
var
     tmpByte3: byte;
     selected_drive: byte;
     new_drives: array[0..1] of byte;
begin

     tmpByte3 := 0;

     while tmpByte3 < 2 do begin

          Writeln;
          Writeln('Select ', tmpArr[tmpByte3], ' drive number (1-8)');

          key := WaitKey('12345678'#27);

          if key = #27 then Break;

          selected_drive := byte(key) - 48;

          if (tmpByte3 = 1) and (selected_drive = new_drives[0]) then begin
               Writeln;
               Writeln ('Destination drive number must be ');
               Writeln ('different than source number.');
               continue;
          end;

          readPercom(selected_drive, true, tmpArr2[tmpByte3]);

          if SIOresult > 127 then continue;

          new_drives[tmpByte3] := selected_drive;

          Delay(50);

          inc(tmpByte3);

     end;

     { Both drives change together, Esc keeps the previous pair }

     if tmpByte3 = 2 then begin
          source_drive := new_drives[0];
          dest_drive := new_drives[1];
     end;

     writeMenu;

end;



label writePercomAbort;
procedure writePercom;
var
     drive: byte;
     sourceOrDestination2: char;
     notConfigurable: boolean;
     requestedSectors: word;
     requestedSectorSize: word;
begin

     Writeln ('S - Source drive');
     Writeln ('D - Destination drive');

     case WaitKey('SD'#27) of
          'S': begin drive := source_drive; sourceOrDestination2 := 's'; notConfigurable := source_drive_not_configurable end;
          'D': begin drive := dest_drive; sourceOrDestination2 := 'd'; notConfigurable := dest_drive_not_configurable end;
          else goto writePercomAbort;
     end;

     if notConfigurable then begin
          Writeln('This drive is not configurable.');
          pressKey;
          goto writePercomAbort;
     end;

     writeln;
     writeln ('Select drive configuration:');
     writeln ('1 - SS SD  (90 KB)');
     writeln ('2 - SS ED (130 KB)');
     writeln ('3 - SS DD (180 KB)');
     writeln ('4 - DS DD (360 KB)');
     writeln ('5 - DS QD (720 KB)');

     key := WaitKey('12345'#27);
     if key = #27 then goto writePercomAbort;

     Move(PERCOM_CONFIGS[(byte(key) - 49) * 12], pointer(PERCOM_BUFFER_MEM), 12);
     decodePercom;
     requestedSectors := number_of_sectors;
     requestedSectorSize := bytes_per_sector;

     exec_sio(drive, WRITE_PERCOM, SIO_WRITE, 7, PERCOM_BUFFER_MEM, 12, 0);

     Writeln;
     errorMessage(SIOresult);

     if SIOresult = SIO_OK then begin
          readPercom(drive, true, sourceOrDestination2);
          if (requestedSectors = number_of_sectors) and (requestedSectorSize = bytes_per_sector) then begin
               Writeln('Configuration confirmed');
          end else begin
               Writeln('Warning. Drive may not support that');
               Writeln('configuration. Proceed with caution!');
          end;
     end;

     pressKey;

     writePercomAbort:

     writeMenu;

end;



function copyError(error_number: byte; current_sector: word; operation: byte) : byte;
var
     operation_type: string[7];
begin

     if operation = 1 then operation_type := 'reading'
     else operation_type:= 'writing';

     Result := ACTION_SKIP;
     progressShown := false;

     case autoAction of

          1:   begin
                    Writeln;
                    Writeln;
                    Writeln('Error ', error_number, ' ', operation_type, ' sector ', current_sector, '.');
                    Writeln('A'*' - Abort, ','R'*' - Retry, ','S'*' - Skip,');

                    if operation = 1 then begin
                         Writeln ('W'*' - write buffer and continue.');
                         tmpString := 'ARSW';
                    end else
                         tmpString := 'ARS';

                    Writeln;

                    case WaitKey(tmpString) of
                         'A': Result := ACTION_ABORT;
                         'R': Result := ACTION_RETRY;
                         'S': Result := ACTION_SKIP;
                         'W': Result := ACTION_WRITE_BUFFER;
                    end;
               end;
          2:   Result := ACTION_ABORT;
          3:   begin
                    if opMaxRetries > 0 then begin
                         dec(opMaxRetries);
                         gotoxy(3, WhereY);
                         Result := ACTION_RETRY;
                    end else
                         Result := ACTION_SKIP;
               end;
          4:   begin Result := ACTION_SKIP; gotoxy(3, WhereY); end;
          5:   if operation = 1 then Result := ACTION_WRITE_BUFFER;

     end;

end;



label writeLogDriveDialog;
procedure writeLog(logFileSize: word);
var
     logFileBuffer: pointer;
     err: byte;
begin

     {$i-}

     logFileBuffer := pointer(LOG_BUFFER);
     logFileSize := logFileSize * LOG_RECORD_SIZE;

     writeLogDriveDialog:

          clearKeys;

          writeln;
          writeln('Enter filename with drive number.');
          writeln('Eg. D1:LOGFILE.LOG');

          readLine(16);

          if breakPressed then begin
               Writeln ('Break key pressed, aborting');
               exit;
          end;

     Assign(f, tmpString);
     Rewrite(f, 1);
     err := IOResult;
     if err < 128 then begin
          Blockwrite(f, logFileBuffer, logFileSize);
          err := IOResult;
     end;
     Close(f);
     if err < 128 then err := IOResult;

     {$i+}

     Writeln;

     if err > 127 then begin
          Writeln ('Error ', err);
          goto writeLogDriveDialog;
     end;

     Writeln ('File saved');

end;



procedure putToLog(info: byte);
var
     sector_number: string[4];
     sector_data: string[7];
begin

     if sectors_to_read <= LOG_MAX_RECORDS then begin
          if operations_number >= log_capacity then begin
               log_is_truncated := true;
          end else begin
               Str(current_sector, sector_number);
               sector_data := '       ';
               Move(sector_number[1], sector_data[5 - Length(sector_number)], Length(sector_number));
               sector_data[5] := Chr(58);
               sector_data[6] := Chr(info);
               sector_data[7] := Chr(EOL);
               move(sector_data[1], pointer(LOG_BUFFER + sector_index), LOG_RECORD_SIZE);
               sector_index := sector_index + LOG_RECORD_SIZE;
               Inc(operations_number);
          end;
     end;

end;



function sectorLength(sector: word): word;
begin
     if sector < 4 then
          Result := 128
     else
          Result := bytes_per_sector_source;
end;



procedure setProgress(const caption: string);
begin
     progressLabel := caption;
     progressShown := false;
end;



{ Prints the label once per line, then only the sector number: screen
  output between SIO calls must stay short to keep up with the sector
  interleave of the disk }
procedure showProgress;
begin
     if not progressShown then begin
          GotoXY(3, WhereY);
          Write(progressLabel);
          progressShown := true;
     end;
     GotoXY(3 + Length(progressLabel), WhereY);
     Write(current_sector, ' ');
end;



{ Reads current_sector into buffer, retrying as long as copyError says so.
  Returns 0 on success, otherwise the copyError action. }
function readSector(buffer: word; sector_length: word): byte;
begin

     opMaxRetries := maxRetries;

     repeat

          showProgress;

          fillbyte(pointer(buffer), sector_length, 0);
          exec_sio(source_drive, READ_SECTOR, SIO_READ, $7, buffer, sector_length, current_sector);

          if SIOresult > 127 then begin
               if logging then putToLog(LOG_READ_ERROR);
               Result := copyError(SIOresult, current_sector, 1);
          end else begin
               if logging then putToLog(LOG_READ_SUCCESS);
               inc(sectors_succesfully_read);
               Result := 0;
          end;

     until Result <> ACTION_RETRY;

end;



{ Writes buffer to current_sector, retrying as long as copyError says so.
  Returns 0 on success, otherwise the copyError action. }
function writeSector(buffer: word; sector_length: word; command: byte): byte;
begin

     opMaxRetries := maxRetries;

     repeat

          showProgress;

          exec_sio(dest_drive, command, SIO_WRITE, $7, buffer, sector_length, current_sector);

          if SIOresult > 127 then begin
               if logging then putToLog(LOG_WRITE_ERROR);
               Result := copyError(SIOresult, current_sector, 2);
          end else
               Result := 0;

     until Result <> ACTION_RETRY;

end;



{ fast = false: read and write a chosen range sector by sector.
  fast = true: copy the whole disk, reading as many sectors as fit in
  memory, then writing them. }
label startSector, endSector, startCopy, copyExit;
procedure copy(fast: boolean);
var
     writeCommand: byte;
     action: byte;
     aborted: boolean;
     last_sector: word;
     buffer_start: word;
     buffer: word;
     batch_sectors: word;
     batch_first: word;
     batch_last: word;
     slot: word;
begin

     readPercom(source_drive, true, 's');
     readPercom(dest_drive, true, 'd');

     if bytes_per_sector_source = 0 then begin
          Writeln ('Source drive is not ready.');
          pressKey;
          goto copyExit;
     end;

     if bytes_per_sector_dest = 0 then begin
          Writeln ('Destination drive is not ready.');
          pressKey;
          goto copyExit;
     end;

     if bytes_per_sector_source <> bytes_per_sector_dest then begin
          Writeln('Sector size in destination drive do ');
          Writeln('not match sector size in source ');
          Writeln('drive. Would you like to match');
          Writeln('densities? Destination drive will be');
          Writeln('formatted and data will be lost (Y/N)');

          if WaitKey('YN') = 'N' then goto copyExit;

          matchDrives;

          if not matchSuccess then begin
               Writeln('Matching failed, aborting');
               if oldPercomValid then begin
                    exec_sio(dest_drive, READ_STATUS, SIO_READ, 7, PERCOM_BUFFER_MEM, 4, 0);
                    exec_sio(dest_drive, WRITE_PERCOM, SIO_WRITE, 7, PERCOM_BUFFER_MEM_OLD, 12, 0);
               end;
               pressKey;
               goto copyExit;
          end;
     end;

     if fast then begin
          start_sector := 1;
          end_sector := sectors_source;
          goto startCopy;
     end;

     startSector:

          writeln('Start sector:');
          readLine(6);

          if breakPressed then begin
               Writeln ('Break key pressed, aborting');
               Goto copyExit;
          end;

          Val(tmpString, start_sector, Code);

          if Code > 0 then goto startSector;

          if start_sector < 1 then begin
               writeln ('Lowest sector number is 1');
               goto startSector;
          end;

          if word(start_sector) > sectors_source then begin
               writeln ('Start sector is greater than total');
               writeln ('number of sectors.');
               goto startSector;
          end;

     endSector:

          writeln('End sector:');
          readLine(6);

          if breakPressed then begin
               Writeln ('Break key pressed, aborting');
               Goto copyExit;
          end;

          val(tmpString, end_sector, Code);

          if Code > 0 then goto endSector;

          if end_sector < start_sector then begin
               writeln ('End sector is lesser than start');
               writeln ('sector.');
               goto endSector;
          end;

          if word(end_sector) > sectors_source then begin
               writeln ('End sector is greater than total ');
               writeln ('number of sectors.');
               writeln ('Would you like to override data');
               writeln ('reported by drive? (Y/N)');
               writeln;
               writeln ('Warning!'*,' This can lead to unexpected');
               writeln ('results and the disk may be unusable');

               if WaitKey('YN') = 'N' then goto endSector;
          end;

     startCopy:

     sectors_succesfully_read := 0;
     operations_number := 0;
     log_is_truncated := false;
     aborted := false;
     last_sector := end_sector;
     sectors_to_read := last_sector - word(start_sector) + 1;

     { Memory from LOG_BUFFER up to MEMTOP holds the log in sector by sector
       mode and the sector buffer in fast mode, which keeps no log. }

     logging := createLog and not fast;

     log_capacity := 0;
     if logging then begin
          log_capacity := (MEMTOP + 1 - LOG_BUFFER) div LOG_RECORD_SIZE;
          if log_capacity > LOG_MAX_RECORDS then log_capacity := LOG_MAX_RECORDS;
     end;

     buffer_start := LOG_BUFFER;
     batch_sectors := (MEMTOP + 1 - buffer_start) div bytes_per_sector_source;
     if batch_sectors > MAX_BATCH_SECTORS then batch_sectors := MAX_BATCH_SECTORS;

     writeln('Copying ', sectors_to_read, ' sectors.');
     if fast then writeln('Buffer: ', batch_sectors, ' sectors.');

     CursorOff;
     if logging then clearLogBuffer;
     sector_index := 0;

     if verify then
          writeCommand := PUT_SECTOR_WITH_VERIFY
     else
          writeCommand := PUT_SECTOR;

     Writeln;

     current_sector := start_sector;

     if not fast then begin

          setProgress('Reading and writing sector #');

          while current_sector <= last_sector do begin

               action := readSector(COPY_BUFFER_MEM, sectorLength(current_sector));

               if action = ACTION_ABORT then begin aborted := true; break; end;

               { Write the buffer unless the sector was skipped }

               if action <> ACTION_SKIP then
                    if writeSector(COPY_BUFFER_MEM, sectorLength(current_sector), writeCommand) = ACTION_ABORT then begin
                         aborted := true;
                         break;
                    end;

               inc(current_sector);

          end;

     end else begin

          while current_sector <= last_sector do begin

               batch_first := current_sector;
               batch_last := batch_first + batch_sectors - 1;
               if batch_last > last_sector then batch_last := last_sector;

               { Read pass }

               setProgress('Reading sector #');
               slot := 0;
               buffer := buffer_start;

               while current_sector <= batch_last do begin
                    action := readSector(buffer, sectorLength(current_sector));
                    if action = ACTION_ABORT then begin aborted := true; break; end;
                    skipSector[slot] := action = ACTION_SKIP;
                    inc(slot);
                    inc(buffer, bytes_per_sector_source);
                    inc(current_sector);
               end;

               if aborted then break;

               { Write pass, sectors skipped while reading are not written }

               setProgress('Writing sector #');
               slot := 0;
               buffer := buffer_start;
               current_sector := batch_first;

               while current_sector <= batch_last do begin
                    if not skipSector[slot] then
                         if writeSector(buffer, sectorLength(current_sector), writeCommand) = ACTION_ABORT then begin
                              aborted := true;
                              break;
                         end;
                    inc(slot);
                    inc(buffer, bytes_per_sector_source);
                    inc(current_sector);
               end;

               if aborted then break;

          end;

     end;

     CursorOn;

     Writeln;
     Writeln;
     if aborted then
          Writeln ('Copy aborted at sector ', current_sector, '.')
     else
          Writeln ('Copy finished.');
     Writeln (sectors_succesfully_read, ' sectors read.');
     Writeln (sectors_to_read - sectors_succesfully_read, ' sectors not read.');

     if logging and (sectors_to_read <= LOG_MAX_RECORDS) then begin

          Writeln;

          if log_is_truncated then begin
               Writeln ('Due to memory limit, log file');
               Writeln ('is truncated.');
          end;

          Writeln ('Write log file to disk? (Y/N)');

          if WaitKey('YN') = 'N' then goto copyExit;

          writeLog(operations_number);

     end;

     pressKey;

     copyExit:

     writeMenu;

end;



label optionsAbort;
procedure setOptions;
begin

     writeln;
     writeln ('Log copy operations? (Y/N)');

     case WaitKey('YN'#27) of
          'Y': createLog := true;
          'N': createLog := false;
          else goto optionsAbort;
     end;

     writeln;
     writeln ('Verify writes? (Y/N)');

     case WaitKey('YN'#27) of
          'Y': verify := true;
          'N': verify := false;
          else goto optionsAbort;
     end;

     writeln;
     writeln ('Auto action when copy error occured:');
     writeln ('1 - ask');
     writeln ('2 - abort');
     writeln ('3 - retry');
     writeln ('4 - skip');
     writeln ('5 - write buffer and continue');

     key := WaitKey('12345'#27);
     if key = #27 then goto optionsAbort;
     autoAction := byte(key) - 48;

     if autoAction = 3 then begin

          repeat
               writeln;
               writeln ('Retry attempts (1-99)');

               readLine(3);

               if breakPressed then begin
                    Writeln ('Break key pressed, aborting');
                    goto optionsAbort;
               end;

               Val(tmpString, maxRetries, Code);

          until (Code = 0) and (maxRetries >= 1) and (maxRetries <= 99);

     end;

     optionsAbort:

     writeMenu;

end;


{ autoAction = what to do when copy error occured }
{ 1 - ask }
{ 2 - abort }
{ 3 - retry }
{ 4 - skip }
{ 5 - write buffer }

begin

     verify       := false;
     autoAction   := 1;
     maxRetries   := 3;
     createLog    := true;

     source_drive := 1;
     dest_drive   := 2;

     ClrScr;
     clearPercomBuffer;

     writeln ('MILF 0.9 - dely/bjb 2020-2021');
     writeln;

     writeMenu;

     repeat

          case WaitKey('RWFDCMXOQB') of
               'R' : writeMenu;
               'W' : writePercom;
               'F' : format;
               'D' : changeDrives;
               'C' : copy(false);
               'M' : copy(true);
               'X' : swapDrives;
               'O' : setOptions;
               'Q' : exitToDOS;
               'B' : coldStart;
          end;

     until false;

end.
