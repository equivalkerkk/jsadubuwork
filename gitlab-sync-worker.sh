#!/bin/bash

# GitLab Repository Sync Script for Ubuntu Server
# Bu script GitLab repolarını her 5 dakikada günceller

# GitLab Token - Buraya gerçek token'ınızı yazın
GITLAB_TOKEN="your_gitlab_token_here"

# GitLab Repository URLs (Python script'ten alınan)
GITLAB_REPOS=(
    "equalizer2/facebook-report-bot"
    "equalizer2/instagram-report-bot"
    "equalizer2/telegram-mass-report-bot"
    "equalizer2/tiktok-mass-report-bot"
    "equalizer2/whatsapp-mass-report-bot"
)

# Commit mesajları (rastgele seçim için)
COMMIT_MESSAGES=(
    "Fix minor formatting issues"
    "Update documentation"
    "Improve code structure"
    "Minor bug fixes"
    "Performance improvements"
    "Update project dependencies"
    "Code cleanup and optimization"
    "Fix compatibility issues"
    "Update configuration"
    "Minor improvements and fixes"
)

# Log dosyası
LOG_FILE="/var/log/gitlab-sync-worker.log"

# Timestamp fonksiyonu
timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Log fonksiyonu
log() {
    echo "[$(timestamp)] $1" | tee -a "$LOG_FILE"
}

# Rastgele commit mesajı seç
get_random_commit_message() {
    echo "${COMMIT_MESSAGES[$RANDOM % ${#COMMIT_MESSAGES[@]}]}"
}

# GitLab API ile repo güncelle
update_gitlab_repo_api() {
    local project_path="$1"
    local repo_name=$(basename "$project_path")
    
    log "Updating GitLab repository via API: $repo_name"
    
    # URL encode project path
    local encoded_path=$(echo "$project_path" | sed 's/\//%2F/g')
    local api_url="https://gitlab.com/api/v4/projects/$encoded_path"
    
    # Mevcut proje bilgilerini al
    local project_response=$(curl -s -H "Authorization: Bearer $GITLAB_TOKEN" \
        -H "Content-Type: application/json" \
        "$api_url")
    
    if [[ $? -ne 0 ]]; then
        log "Error: Failed to fetch project info for $repo_name"
        return 1
    fi
    
    # Description'ı çıkar
    local current_description=$(echo "$project_response" | jq -r '.description // ""')
    
    # Timestamp marker oluştur
    local timestamp_marker=$(date +%s)
    local marker_id=$((timestamp_marker % 100))
    
    # Description'ı güncelle
    local new_description
    if echo "$current_description" | grep -q "<!-- [0-9]* -->"; then
        # Mevcut marker'ı kaldır
        new_description=$(echo "$current_description" | sed 's/<!-- [0-9]* -->//g' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')
    else
        # Yeni marker ekle
        new_description="$current_description <!-- $marker_id -->"
    fi
    
    # Repository'yi güncelle
    local update_response=$(curl -s -X PUT \
        -H "Authorization: Bearer $GITLAB_TOKEN" \
        -H "Content-Type: application/json" \
        "$api_url" \
        -d "{\"description\": \"$new_description\"}")
    
    if [[ $? -eq 0 ]] && echo "$update_response" | jq -e '.id' > /dev/null 2>&1; then
        log "Successfully updated $repo_name via API"
        return 0
    else
        log "Failed to update $repo_name via API"
        return 1
    fi
}

# GitLab repo güncelle (file commit yöntemi)
update_gitlab_repo_commit() {
    local project_path="$1"
    local repo_name=$(basename "$project_path")
    local temp_dir="/tmp/gitlab-sync-$(date +%s)"
    
    log "Updating GitLab repository via commit: $repo_name"
    
    # Temporary directory oluştur
    mkdir -p "$temp_dir"
    cd "$temp_dir"
    
    # GitLab'dan clone et
    local gitlab_url="https://oauth2:$GITLAB_TOKEN@gitlab.com/$project_path.git"
    
    if ! git clone "$gitlab_url" "$repo_name" 2>/dev/null; then
        log "Failed to clone $repo_name from GitLab"
        rm -rf "$temp_dir"
        return 1
    fi
    
    cd "$repo_name"
    
    # Ana branch'i belirle
    local main_branch
    if git branch -r | grep -q 'origin/main'; then
        main_branch="main"
    else
        main_branch="master"
    fi
    
    # Ana branch'e checkout et
    if ! git checkout "$main_branch" 2>/dev/null; then
        log "Failed to checkout $main_branch for $repo_name"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Git config ayarla
    git config user.email "sync@gitlab.com"
    git config user.name "GitLab Sync"
    
    # README.md dosyasını güncelle
    local current_date=$(date '+%Y-%m-%d')
    local readme_updated=false
    
    if [[ -f README.md ]]; then
        # Mevcut README'yi güncelle
        if grep -q "Updated:" README.md; then
            sed -i "s/Updated: [0-9-]*/Updated: $current_date/g" README.md
            readme_updated=true
        elif grep -q "Last updated:" README.md; then
            sed -i "s/Last updated: [0-9-]*/Last updated: $current_date/g" README.md
            readme_updated=true
        else
            # Dosya sonuna güncelleme tarihi ekle
            echo "" >> README.md
            echo "---" >> README.md
            echo "*Last updated: $current_date*" >> README.md
            readme_updated=true
        fi
    else
        # README.md oluştur
        cat > README.md << EOF
# $repo_name

## Project Status
This project is actively maintained and updated regularly.

## Features
- High performance
- Reliable operation
- Regular updates

---
*Last updated: $current_date*
EOF
        readme_updated=true
    fi
    
    # Değişiklikleri ekle
    if [[ "$readme_updated" == true ]]; then
        git add README.md
        
        # Rastgele commit mesajı seç
        local commit_message=$(get_random_commit_message)
        
        # Commit yap
        if git commit -m "$commit_message" 2>/dev/null; then
            # GitLab'a push et
            if git push origin "$main_branch" 2>/dev/null; then
                log "Successfully updated $repo_name on GitLab"
                rm -rf "$temp_dir"
                return 0
            else
                log "Failed to push update to GitLab for $repo_name"
            fi
        else
            log "No changes to commit for $repo_name"
        fi
    fi
    
    rm -rf "$temp_dir"
    return 1
}

# Ana güncelleme fonksiyonu
update_gitlab_repo() {
    local project_path="$1"
    
    # Önce API ile dene
    if update_gitlab_repo_api "$project_path"; then
        return 0
    fi
    
    # API başarısız olursa commit yöntemi ile dene
    log "API update failed, trying file commit method"
    update_gitlab_repo_commit "$project_path"
}

# Ana fonksiyon
main() {
    log "GitLab Repository Update started"
    
    # GITLAB_TOKEN kontrolü
    if [[ "$GITLAB_TOKEN" == "your_gitlab_token_here" ]] || [[ -z "$GITLAB_TOKEN" ]]; then
        log "Error: Please set your GITLAB_TOKEN in the script"
        exit 1
    fi
    
    # Gerekli araçları kontrol et
    for tool in curl jq git; do
        if ! command -v "$tool" &> /dev/null; then
            log "Error: $tool is not installed"
            exit 1
        fi
    done
    
    log "Updating GitLab repositories..."
    
    local success_count=0
    local total_repos=${#GITLAB_REPOS[@]}
    
    # Tüm repoları güncelle
    for repo in "${GITLAB_REPOS[@]}"; do
        if update_gitlab_repo "$repo"; then
            ((success_count++))
        fi
        
        # Repos arasında kısa bekleme
        sleep 2
    done
    
    log "Final Result: $success_count/$total_repos repositories updated"
    
    if [[ $success_count -eq $total_repos ]]; then
        log "🎉 All repositories updated successfully!"
        log "🔥 Your GitLab repositories should now appear at the top!"
    else
        log "⚠️ Warning: $((total_repos - success_count)) repositories had issues"
        if [[ $success_count -gt 0 ]]; then
            log "✅ $success_count repositories were updated successfully"
        fi
    fi
    
    log "GitLab Repository Update completed"
}

# Script'i çalıştır
main "$@" 