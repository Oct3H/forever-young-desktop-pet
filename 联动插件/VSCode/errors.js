'use strict';
const path=require('path'),crypto=require('crypto');
const clean=value=>String(value || '').replace(/\x1b\[[0-9;]*m/g,'').replace(/[\x00-\x08\x0b\x0c\x0e-\x1f]/g,'').trim().slice(0,400);
function compilerError(output,file) {
  for(const line of String(output).split(/\r?\n/)) {
    const match=line.match(/^(.+):(\d+):(\d+):\s*(?:fatal )?error:\s*(.+)$/);
    if(match) return {errorFile:path.resolve(path.dirname(file),match[1]),errorLine:match[2],errorColumn:match[3],errorSummary:clean(match[4]),errorKind:'compile'};
  }
  return {errorSummary:clean(output.split(/\r?\n/).find(line=>/error:|undefined symbols|linker command failed/i.test(line))) || 'Compilation failed. See the build terminal.',errorKind:'compile'};
}
function stamp(error) {return {...error,errorToken:crypto.createHash('sha256').update(JSON.stringify(error)).digest('hex')};}
exports.compilerError=compilerError;exports.stamp=stamp;exports.clean=clean;
