#! /usr/bin/env ruby

libpath = File.absolute_path(File.dirname(__FILE__)) +
  "/../../../../../../narray/lib"
$LOAD_PATH.unshift libpath

require "erbpp"
require "optparse"
require_relative "erbpp_gsl_sys"

tmpfile = ".cogen.tmp"
outfile = nil

opts = OptionParser.new
opts.on("-l"){|v| require "erbpp/line_number" }
opts.on("-o FILE"){|v| outfile=v; $stdout=open(tmpfile,"w") }
opts.parse!(ARGV)

erb_path, type_file = ARGV
DefineSys.new(erb_path) do
  load_func_def "gen/func_def.rb"
  load_const_def "gen/const_def.rb"
  run
end

if outfile
  require "fileutils"
  FileUtils.mv(tmpfile,outfile)
end
