name: Extract Archive.zip to Repo

on:
  workflow_dispatch:
    inputs:
      zip_file:
        description: 'ZIP file path'
        required: true
        default: 'Archive.zip'
        type: string
      delete_zip:
        description: 'Delete ZIP after successful extract?'
        required: true
        type: boolean
        default: true

permissions:
  contents: write

jobs:
  extract:
    name: Extract and Commit
    runs-on: ubuntu-latest
    timeout-minutes: 10

    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Verify ZIP
        run: |
          ZIP="${{ github.event.inputs.zip_file }}"
          test -f "$ZIP" || { echo "ZIP not found: $ZIP"; exit 1; }
          echo "=== ZIP info ==="
          ls -lh "$ZIP"
          echo ""
          echo "=== Top-level contents ==="
          unzip -l "$ZIP" | head -50

      - name: Extract to temp
        run: |
          rm -rf /tmp/extract
          mkdir -p /tmp/extract
          unzip -q "${{ github.event.inputs.zip_file }}" -d /tmp/extract
          echo "=== Extracted tree ==="
          ls -la /tmp/extract/

      - name: Detect ZIP root
        id: root
        run: |
          cd /tmp/extract
          COUNT=$(ls -1 | wc -l)
          FIRST=$(ls -1 | head -1)
          if [ "$COUNT" = "1" ] && [ -d "$FIRST" ]; then
            echo "path=/tmp/extract/$FIRST" >> $GITHUB_OUTPUT
            echo "Detected single root: $FIRST"
          else
            echo "path=/tmp/extract" >> $GITHUB_OUTPUT
            echo "Using extract root directly"
          fi

      - name: Show what will be copied
        run: |
          ROOT="${{ steps.root.outputs.path }}"
          echo "=== Source: $ROOT ==="
          ls -la "$ROOT" | head -30
          echo ""
          echo "=== Repo before ==="
          ls -la

      - name: Overlay-copy files into repo
        run: |
          ROOT="${{ steps.root.outputs.path }}"
          # Overlay copy: ZIP files overwrite repo files with same path
          cp -R "$ROOT"/. ./ 2>/dev/null || true

          # Remove any nested .git if ZIP carried one
          if [ -d "./.git-zip" ]; then rm -rf ./.git-zip; fi

          echo "=== Repo after copy ==="
          ls -la

      - name: Delete ZIP (optional)
        if: ${{ github.event.inputs.delete_zip == 'true' }}
        run: |
          rm -f "${{ github.event.inputs.zip_file }}"
          echo "Deleted ${{ github.event.inputs.zip_file }}"

      - name: Commit and push
        run: |
          git config user.name  "AetherEngine Bot"
          git config user.email "bot@aether.local"
          git add -A
          if git diff --cached --quiet; then
            echo "No changes to commit"
            exit 0
          fi
          git commit -m "Extract ${{ github.event.inputs.zip_file }} into repo"
          git push

      - name: Summary
        if: always()
        run: |
          echo "### Extract Summary" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "- **ZIP:** \`${{ github.event.inputs.zip_file }}\`" >> $GITHUB_STEP_SUMMARY
          echo "- **Deleted ZIP:** ${{ github.event.inputs.delete_zip }}" >> $GITHUB_STEP_SUMMARY
          echo "- **Root used:** \`${{ steps.root.outputs.path }}\`" >> $GITHUB_STEP_SUMMARY
