#!/bin/bash

###############################################################################
# Sistem Kaynak İzleme Script'i
# CPU, RAM ve Ağ Trafiğini haftalık olarak kaydeder ve rapor oluşturur
###############################################################################

# Ayarlar
LOG_DIR="$HOME/system_logs"
LOG_FILE="$LOG_DIR/system_monitor.log"
REPORT_FILE="$LOG_DIR/weekly_report.txt"
SAMPLE_INTERVAL=300  # 5 dakika (saniye cinsinden)

# Dizin oluştur
mkdir -p "$LOG_DIR"

# Renkli çıktı için
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

###############################################################################
# Fonksiyonlar
###############################################################################

# CPU kullanımını al
get_cpu_usage() {
    top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1
}

# RAM kullanımını al
get_ram_usage() {
    free | grep Mem | awk '{printf "%.2f", ($3/$2) * 100.0}'
}

# Ağ trafiğini al (gönderilen ve alınan toplam byte)
get_network_stats() {
    # Ana ağ arayüzünü bul (lo hariç)
    INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    
    if [ -z "$INTERFACE" ]; then
        INTERFACE="eth0"
    fi
    
    # RX (alınan) ve TX (gönderilen) bytes
    RX_BYTES=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes 2>/dev/null || echo "0")
    TX_BYTES=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes 2>/dev/null || echo "0")
    
    # MB cinsine çevir
    RX_MB=$(echo "scale=2; $RX_BYTES / 1048576" | bc)
    TX_MB=$(echo "scale=2; $TX_BYTES / 1048576" | bc)
    
    echo "$INTERFACE|$RX_MB|$TX_MB"
}

# Log kaydı yap
log_stats() {
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    CPU=$(get_cpu_usage)
    RAM=$(get_ram_usage)
    NETWORK=$(get_network_stats)
    
    echo "$TIMESTAMP|$CPU|$RAM|$NETWORK" >> "$LOG_FILE"
}

# Haftalık rapor oluştur
generate_weekly_report() {
    echo -e "${GREEN}=== HAFTALİK SİSTEM KAYNAK RAPORU ===${NC}" > "$REPORT_FILE"
    echo "Rapor Tarihi: $(date '+%Y-%m-%d %H:%M:%S')" >> "$REPORT_FILE"
    echo "========================================" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Son 7 günlük veriyi al
    WEEK_AGO=$(date -d '7 days ago' '+%Y-%m-%d')
    
    if [ ! -f "$LOG_FILE" ]; then
        echo "Henüz log verisi bulunmuyor." >> "$REPORT_FILE"
        return
    fi
    
    # Geçici dosya oluştur
    TEMP_FILE="/tmp/weekly_data_$$.txt"
    grep -E "^[0-9]{4}-[0-9]{2}-[0-9]{2}" "$LOG_FILE" | \
        awk -F'|' -v week="$WEEK_AGO" '$1 >= week' > "$TEMP_FILE"
    
    if [ ! -s "$TEMP_FILE" ]; then
        echo "Son 7 günde veri kaydı bulunamadı." >> "$REPORT_FILE"
        rm -f "$TEMP_FILE"
        return
    fi
    
    # Günlük bazda özet
    echo "=== GÜNLÜK ORTALAMALAR ===" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    for i in {0..6}; do
        DAY=$(date -d "$i days ago" '+%Y-%m-%d')
        DAY_NAME=$(date -d "$i days ago" '+%A')
        
        DAY_DATA=$(grep "^$DAY" "$TEMP_FILE")
        
        if [ -z "$DAY_DATA" ]; then
            continue
        fi
        
        # CPU ortalaması
        CPU_AVG=$(echo "$DAY_DATA" | awk -F'|' '{sum+=$2; count++} END {if(count>0) printf "%.2f", sum/count; else print "0"}')
        CPU_MAX=$(echo "$DAY_DATA" | awk -F'|' '{max=$2; for(i=2;i<=NF;i++) if($2>max) max=$2} END {print max}')
        
        # RAM ortalaması
        RAM_AVG=$(echo "$DAY_DATA" | awk -F'|' '{sum+=$3; count++} END {if(count>0) printf "%.2f", sum/count; else print "0"}')
        RAM_MAX=$(echo "$DAY_DATA" | awk -F'|' '{max=$3; for(i=3;i<=NF;i++) if($3>max) max=$3} END {print max}')
        
        # Ağ trafiği toplamı
        RX_SUM=$(echo "$DAY_DATA" | awk -F'|' 'BEGIN{sum=0; prev=0} {if(NR==1) prev=$5; else {diff=$5-prev; if(diff>0) sum+=diff; prev=$5}} END {printf "%.2f", sum}')
        TX_SUM=$(echo "$DAY_DATA" | awk -F'|' 'BEGIN{sum=0; prev=0} {if(NR==1) prev=$6; else {diff=$6-prev; if(diff>0) sum+=diff; prev=$6}} END {printf "%.2f", sum}')
        
        echo "[$DAY - $DAY_NAME]" >> "$REPORT_FILE"
        echo "  CPU: Ort: ${CPU_AVG}% | Max: ${CPU_MAX}%" >> "$REPORT_FILE"
        echo "  RAM: Ort: ${RAM_AVG}% | Max: ${RAM_MAX}%" >> "$REPORT_FILE"
        echo "  Ağ: İndirilen: ${RX_SUM} MB | Yüklenen: ${TX_SUM} MB" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    done
    
    # Haftalık genel özet
    echo "=== HAFTALİK GENEL ÖZET ===" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    CPU_WEEK_AVG=$(awk -F'|' '{sum+=$2; count++} END {printf "%.2f", sum/count}' "$TEMP_FILE")
    CPU_WEEK_MAX=$(awk -F'|' 'BEGIN{max=0} {if($2>max) max=$2} END {print max}' "$TEMP_FILE")
    
    RAM_WEEK_AVG=$(awk -F'|' '{sum+=$3; count++} END {printf "%.2f", sum/count}' "$TEMP_FILE")
    RAM_WEEK_MAX=$(awk -F'|' 'BEGIN{max=0} {if($3>max) max=$3} END {print max}' "$TEMP_FILE")
    
    echo "CPU: Haftalık Ortalama: ${CPU_WEEK_AVG}% | Maksimum: ${CPU_WEEK_MAX}%" >> "$REPORT_FILE"
    echo "RAM: Haftalık Ortalama: ${RAM_WEEK_AVG}% | Maksimum: ${RAM_WEEK_MAX}%" >> "$REPORT_FILE"
    
    rm -f "$TEMP_FILE"
    
    echo "" >> "$REPORT_FILE"
    echo "========================================" >> "$REPORT_FILE"
    echo "Detaylı log dosyası: $LOG_FILE" >> "$REPORT_FILE"
}

# Raporu göster
show_report() {
    if [ -f "$REPORT_FILE" ]; then
        cat "$REPORT_FILE"
    else
        echo -e "${RED}Henüz rapor oluşturulmamış.${NC}"
        echo "Önce 'start' komutuyla izlemeyi başlatın."
    fi
}

# İzleme başlat
start_monitoring() {
    if [ -f "$LOG_DIR/monitor.pid" ]; then
        PID=$(cat "$LOG_DIR/monitor.pid")
        if ps -p $PID > /dev/null 2>&1; then
            echo -e "${YELLOW}İzleme zaten çalışıyor (PID: $PID)${NC}"
            return
        fi
    fi
    
    echo -e "${GREEN}Sistem izleme başlatılıyor...${NC}"
    echo "Log dosyası: $LOG_FILE"
    echo "Her $SAMPLE_INTERVAL saniyede bir örnek alınacak."
    
    # Arka planda sürekli çalış
    (
        while true; do
            log_stats
            sleep $SAMPLE_INTERVAL
        done
    ) &
    
    echo $! > "$LOG_DIR/monitor.pid"
    echo -e "${GREEN}İzleme başlatıldı (PID: $!)${NC}"
}

# İzleme durdur
stop_monitoring() {
    if [ -f "$LOG_DIR/monitor.pid" ]; then
        PID=$(cat "$LOG_DIR/monitor.pid")
        if ps -p $PID > /dev/null 2>&1; then
            kill $PID
            rm "$LOG_DIR/monitor.pid"
            echo -e "${GREEN}İzleme durduruldu.${NC}"
        else
            echo -e "${YELLOW}İzleme zaten çalışmıyor.${NC}"
            rm "$LOG_DIR/monitor.pid"
        fi
    else
        echo -e "${YELLOW}İzleme çalışmıyor.${NC}"
    fi
}

# Durum kontrolü
check_status() {
    if [ -f "$LOG_DIR/monitor.pid" ]; then
        PID=$(cat "$LOG_DIR/monitor.pid")
        if ps -p $PID > /dev/null 2>&1; then
            echo -e "${GREEN}İzleme aktif (PID: $PID)${NC}"
            echo "Log dosyası: $LOG_FILE"
            echo "Log boyutu: $(du -h "$LOG_FILE" 2>/dev/null | cut -f1)"
        else
            echo -e "${RED}İzleme çalışmıyor (eski PID dosyası mevcut)${NC}"
        fi
    else
        echo -e "${RED}İzleme çalışmıyor${NC}"
    fi
}

###############################################################################
# Ana Program
###############################################################################

case "$1" in
    start)
        start_monitoring
        ;;
    stop)
        stop_monitoring
        ;;
    status)
        check_status
        ;;
    report)
        generate_weekly_report
        show_report
        ;;
    show)
        show_report
        ;;
    log)
        log_stats
        echo -e "${GREEN}Anlık log kaydı eklendi.${NC}"
        ;;
    *)
        echo "Kullanım: $0 {start|stop|status|report|show|log}"
        echo ""
        echo "Komutlar:"
        echo "  start   - İzlemeyi başlat (arka planda çalışır)"
        echo "  stop    - İzlemeyi durdur"
        echo "  status  - İzleme durumunu kontrol et"
        echo "  report  - Haftalık rapor oluştur ve göster"
        echo "  show    - Son oluşturulan raporu göster"
        echo "  log     - Anlık bir log kaydı ekle"
        echo ""
        echo "Örnek kullanım:"
        echo "  $0 start    # İzlemeyi başlat"
        echo "  $0 report   # Haftalık rapor al"
        echo "  $0 stop     # İzlemeyi durdur"
        exit 1
        ;;
esac
