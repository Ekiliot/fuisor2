#!/usr/bin/env node

import { execSync } from 'child_process';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const rootDir = join(__dirname, '../..');

/**
 * Automatic push script to GitHub repository ekiliot/fuisor2
 * 
 * This script automatically stages, commits, and pushes changes to GitHub.
 * It performs automatic push operations to the ekiliot/fuisor2 repository.
 * 
 * Features:
 * - Automatic staging of all changes
 * - Automatic commit with timestamp
 * - Automatic push to GitHub (ekiliot/fuisor2)
 * 
 * Usage: npm run auto-push or npm run push
 * 
 * Pushes to the 'backend' remote which points to ekiliot/fuisor2
 */

function executeCommand(command, cwd = rootDir) {
  try {
    console.log(`Executing: ${command}`);
    const output = execSync(command, { 
      cwd, 
      encoding: 'utf-8',
      stdio: 'inherit'
    });
    return output;
  } catch (error) {
    console.error(`Error executing command: ${command}`);
    console.error(error.message);
    process.exit(1);
  }
}

function getCurrentBranch() {
  try {
    return execSync('git rev-parse --abbrev-ref HEAD', { 
      encoding: 'utf-8',
      cwd: rootDir 
    }).trim();
  } catch (error) {
    console.error('Error getting current branch');
    process.exit(1);
  }
}

function hasChanges() {
  try {
    const status = execSync('git status --porcelain', { 
      encoding: 'utf-8',
      cwd: rootDir 
    });
    return status.trim().length > 0;
  } catch (error) {
    return false;
  }
}

function hasUnpushedCommits() {
  try {
    execSync('git fetch backend', { cwd: rootDir, stdio: 'ignore' });
    const status = execSync('git status -sb', { 
      encoding: 'utf-8',
      cwd: rootDir 
    });
    return status.includes('ahead');
  } catch (error) {
    return false;
  }
}

function main() {
  console.log('🚀 Automatic push to GitHub (ekiliot/fuisor2)');
  console.log('==============================================\n');

  const branch = getCurrentBranch();
  console.log(`Current branch: ${branch}\n`);

  // Check if there are uncommitted changes
  let hasCommitted = false;
  if (hasChanges()) {
    console.log('📝 Staging all changes...');
    executeCommand('git add -A');
    
    console.log('\n💾 Committing changes...');
    const timestamp = new Date().toISOString();
    const commitMessage = `Automatic push: ${timestamp}`;
    executeCommand(`git commit -m "${commitMessage}"`);
    hasCommitted = true;
  } else {
    console.log('✅ No uncommitted changes found');
  }

  // Check if there are unpushed commits (re-check after potential commit)
  if (hasCommitted || hasUnpushedCommits()) {
    console.log('\n📤 Pushing to GitHub (ekiliot/fuisor2)...');
    executeCommand(`git push backend ${branch}`);
    console.log('\n✅ Successfully pushed to GitHub!');
  } else {
    console.log('\n✅ No changes to push');
  }

  console.log('\n✨ Automatic push completed!');
}

main();

