#!/bin/bash

# System Backup - Skrypt do tworzenia backupu na serwerze AWS S3
# Autor: Robert Szumlas
# Licencja: MIT

# Ustawienia domyślne
backup_dir=""
config_file="config/backup.rc"
s3_bucket=""
s3_destination=""
remove_backups=false
download_dir=""
version=""

# Informacje o skrypcie
version_info=$'Backup Manager - Skrypt do tworzenia, usuwania i pobierania backupów wybranych plików/folderów na serwerze AWS S3\nAutor: Robert Szumlas\nLicencja: MIT'

# Funkcja pomocnicza do wyświetlania komunikatów o błędach
print_error() {
  echo "Błąd: $1" >&2
}

# Funkcja do wyświetlania pomocy
display_help() {
  echo "Backup Manager - Skrypt do tworzenia, usuwania i pobierania backupów wybranych plików/folderów na serwerze AWS S3"
  echo "Użycie: $0 [OPCJE]"
  echo "Opcje:"
  echo "  -c <plik_konfiguracyjny>  Ustawia plik konfiguracyjny (domyślnie: backup.rc)"
  echo "  -b <s3_bucket>            Ustawia nazwę S3 bucket"
  echo "  -l <s3_destination>       Ustawia katalog docelowy w S3 bucket (domyślnie: system-backups)"
  echo "  -v                        Wyświetla wersję i autora"
  echo "  -h                        Wyświetla pomoc"
  echo "  -p <backup_dir>           Ustawia ścieżkę pliku/folderu którego kopia zapasowa ma zostać wysłana na serwer"
  echo "  -r                        Usuwa wszystkie kopie zapasowe dla danego pliku"
  echo "  -d <download_dir>         Pobiera backup do podanego folderu"
  echo "  -n <version>              Ustawia numer wersji kopii zapasowej (opcjonalnie)"
}

# Funkcja do odczytywania opcji
parse_options() {
  local OPTIND opt
  local prev_opt=""
  while getopts ":c:b:l:vhp:rd:n:" opt; do
    case $opt in
      c)
        validate_arg "$opt"
        config_file=${OPTARG}
        ;;
      b)
        validate_arg "$opt"
        s3_bucket=${OPTARG}
        ;;
      l)
        validate_arg "$opt"
        s3_destination=${OPTARG}
        ;;
      v)
        display_info
        exit 0
        ;;
      h)
        display_help
        exit 0
        ;;
      p)
        validate_arg "$opt"
        backup_dir=${OPTARG}
        ;;
      r)
        remove_backups=true
        ;;
      d)
        validate_arg "$opt"
        download_dir=${OPTARG}
        ;;
      n)
        validate_arg "$opt"
        version=${OPTARG}
        ;;
      \?)
        print_error "Nieznana opcja: -$OPTARG"
        display_help
        exit 1
        ;;
      :)
        print_error "Opcja -$OPTARG wymaga argumentu."
        display_help
        exit 1
        ;;
    esac
  done
}

# Funkcja do walidacji argumentów
validate_arg() {
  if [ -z "${OPTARG}" ] || [ "${OPTARG:0:1}" == "-" ]; then
    print_error "Nieprawidłowe użycie opcji -$1"
    display_help
    exit 1
  fi
}

# Funkcja wyświetlająca informacje o skrypcie
display_info() {
  echo "$version_info"
}

# Funkcja do wczytywania konfiguracji z pliku
load_configuration() {
  if [[ -f "$config_file" ]]; then
    source "$config_file"
  else
    print_error "Nie można odnaleźć pliku konfiguracyjnego: $config_file"
    exit 1
  fi
}

# Funkcja do pobierania kopii zapasowej z serwera AWS S3
download_backup() {
  echo "Pobieranie kopii zapasowej..."

  # Sprawdzenie czy katalog docelowy istnieje, jeśli nie, to go tworzy
  if [ ! -d "$download_dir" ]; then
    mkdir -p "$download_dir"
    echo "Utworzono katalog: $download_dir"
  fi

  # Pobieranie presigned URL dla kopii zapasowej z serwera AWS S3
  if [ -n "$version" ]; then
    backup_file="${backup_dir}_backup_${version}.tar.gz"
  else
    latest_version=$(get_latest_backup_version)
    if [ -z "$latest_version" ]; then
      print_error "Nie znaleziono kopii zapasowej."
      exit 1
    fi
    backup_file="${backup_dir}_backup_${latest_version}.tar.gz"
  fi

  # Sprawdzenie czy plik kopii zapasowej istnieje na serwerze AWS S3
  if ! aws s3 ls "s3://$s3_bucket/$s3_destination/$backup_file" &> /dev/null; then
    print_error "Kopia zapasowa nie istnieje na serwerze AWS S3."
    exit 1
  fi

  presigned_url=$(aws s3 presign "s3://$s3_bucket/$s3_destination/$backup_file")

  # Wykonanie żądania GET na pobrany presigned URL i zapisanie kopii zapasowej
  curl -o "$download_dir/$backup_file" -L "$presigned_url"

  # Sprawdzenie, czy pobieranie zakończyło się sukcesem
  if [ $? -eq 0 ]; then
    echo "Kopia zapasowa została pomyślnie pobrana i zapisana w: $download_dir/$backup_file"
  else
    print_error "Wystąpił błąd podczas pobierania kopii zapasowej."
  fi
}


# Funkcja do tworzenia backupu
create_backup() {
  echo "Tworzenie kopii zapasowej..."

  # Sprawdzenie poprzedniej wersji backupu
  prev_version=$(get_latest_backup_version)
  if [ -z "$prev_version" ]; then
    version=1
  else
    version=$((prev_version + 1))
  fi

  create_tar_archive

  # Przesyłanie kopii zapasowej na serwer AWS S3
  upload_to_s3_with_spinner

  # Sprawdzenie, czy przesyłanie zakończyło się sukcesem
  if [ $? -eq 0 ]; then
    echo "Kopia zapasowa została pomyślnie przesłana do serwera AWS S3."
  else
    print_error "Wystąpił błąd podczas przesyłania kopii zapasowej do serwera AWS S3."
  fi
}

# Funkcja do pobierania najnowszej wersji backupu
get_latest_backup_version() {
  aws s3 ls "s3://$s3_bucket/$s3_destination/" | awk -v file="$(basename "$backup_dir")" '$NF ~ file"_backup_" && $NF ~ /\.tar\.gz$/ {split($NF, a, "_"); split(a[length(a)], b, "."); version=b[1]; if (version > max) max=version} END {print max}'
}

# Funkcja do tworzenia archiwum tar z plikami
create_tar_archive() {
  # Sprawdzenie czy backup_dir istnieje
  if [ ! -e "$backup_dir" ]; then
    echo "Błąd: Plik lub katalog '$backup_dir' nie istnieje."
    exit 1
  fi

  # Tworzenie nazwy backupu
  backup_name="$(basename "$backup_dir")_backup_$version"

  # Tworzenie archiwum tar z plikami
  backup_file="/tmp/$backup_name.tar.gz"

  # Sprawdzenie czy backup_dir jest plikiem
  if [ -f "$backup_dir" ]; then
    # Backup_dir jest plikiem
    tar -czf "$backup_file" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
  elif [ -d "$backup_dir" ]; then
    # Backup_dir jest katalogiem
    tar -czf "$backup_file" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")/"
  else
    # Nieznany typ backup_dir
    echo "Błąd: '$backup_dir' jest nieznanym typem (nie jest ani plikiem, ani katalogiem)."
    exit 1
  fi
}

# Funkcja do przesyłania kopii zapasowej na serwer AWS S3 z animowanym spinnerem
upload_to_s3_with_spinner() {

  # Uruchomienie procesu przesyłania kopii zapasowej na serwer AWS S3 w tle
  upload_to_s3 &
  local upload_pid=$!

  # Wyświetlanie spinnera dla procesu przesyłania
  spinner "$upload_pid"

  # Oczekiwanie na zakończenie procesu przesyłania
  wait "$upload_pid"
}

# Funkcja do przesyłania kopii zapasowej na serwer AWS S3
upload_to_s3() {
  aws s3 cp "/tmp/$backup_name.tar.gz" "s3://$s3_bucket/$s3_destination/"
}

# Funkcja do wyświetlania spinnera dla podanego PID
spinner() {
  local pid=$1
  local delay=0.1
  local spinstr='|/-\'
  while ps a | awk '{print $1}' | grep -q "$pid"; do
    local temp=${spinstr#?}
    printf "\r[%c] " "$spinstr"  # \r, aby kursor został przesunięty na początek linii
    local spinstr=$temp${spinstr%"$temp"}
    sleep $delay
  done
  printf "\r    \r"  # Czyszczenie lini po spinnerze
}

# Funkcja do usuwania wszystkich kopii zapasowych dla danego pliku
remove_backups() {
  echo "Usuwanie kopii zapasowych..."

  # Sprawdzenie, czy plik konfiguracyjny jest ustawiony
  if [[ -z "$config_file" ]]; then
    print_error "Plik konfiguracyjny nie został ustawiony."
    exit 1
  fi

  # Sprawdzenie, czy bucket S3 został ustawiony
  if [[ -z "$s3_bucket" ]]; then
    print_error "Bucket S3 nie został ustawiony."
    exit 1
  fi

  # Sprawdzenie, czy katalog docelowy w bucket S3 został ustawiony
  if [[ -z "$s3_destination" ]]; then
    print_error "Katalog docelowy w bucket S3 nie został ustawiony."
    exit 1
  fi

  # Pobranie listy kopii zapasowych dla danego pliku
  backup_list=$(aws s3 ls "s3://$s3_bucket/$s3_destination/" | awk -v file="$(basename "$backup_dir")" '$NF ~ file"_backup_" && $NF ~ /\.tar\.gz$/ {print $NF}')

  if [[ -z "$backup_list" ]]; then
    echo "Brak kopii zapasowych do usunięcia."
    exit 0
  fi

  # Wyświetlenie listy kopii zapasowych do usunięcia
  echo "Kopie zapasowe do usunięcia:"
  echo "$backup_list"

  # Potwierdzenie usunięcia kopii zapasowych
  read -p "Czy na pewno chcesz usunąć powyższe kopie zapasowe? (tak/nie) " choice
  case "$choice" in
    tak|TAK|T|t)
      # Usunięcie kopii zapasowych
      for backup_file in $backup_list; do
        aws s3 rm "s3://$s3_bucket/$s3_destination/$backup_file"
      done
      echo "Kopie zapasowe zostały pomyślnie usunięte."
      ;;
    nie|NIE|N|n)
      echo "Anulowano usuwanie kopii zapasowych."
      ;;
    *)
      echo "Nieprawidłowy wybór. Anulowano usuwanie kopii zapasowych."
      ;;
  esac
}

# Funkcja do czyszczenia tymczasowych plików backupu
cleanup() {
  rm -rf "$backup_file"  # Delete the temporary backup directory
}

# Funkcja do obsługi przerwania skryptu
interrupt_handler() {
  echo "Przerwano skrypt."
  cleanup
  exit 1
}

# Funkcja do obsługi wyjścia ze skryptu
exit_handler() {
  cleanup
  exit
}

#=========================================================================================
#                                 Główna część skryptu
#=========================================================================================

# Wczytanie konfiguracji z pliku
load_configuration

# Odczytanie opcji z linii poleceń
parse_options "$@"

# Sprawdzenie, czy podano katalog tymczasowy dla backupu
if [[ -z "$backup_dir" ]]; then
  print_error "Katalog tymczasowy dla backupu nie został ustawiony."
  exit 1
fi

# Sprawdzenie, czy podano nazwę bucketu S3
if [[ -z "$s3_bucket" ]]; then
  print_error "Nazwa bucketu S3 nie została ustawiona."
  exit 1
fi

# Sprawdzenie, czy podano katalog docelowy dla bucketu S3
if [[ -z "$s3_destination" ]]; then
  print_error "Katalog docelowy w bucketu S3 nie został ustawiony."
  exit 1
fi

if [[ -n "$download_dir" ]]; then
  download_backup
  exit 1
fi

# Tworzenie kopii zapasowej
if [[ "$remove_backups" == "false" ]]; then
  create_backup
else
  remove_backups
fi

# Zarejestruj obsługę sygnału przerwania (Ctrl+C)
trap interrupt_handler SIGINT

# Zarejestruj obsługę sygnału wyjścia ze skryptu
trap exit_handler EXIT
