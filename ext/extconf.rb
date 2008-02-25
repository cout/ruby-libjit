require 'mkmf'

if not have_library('jit', 'jit_init', []) then
  $stderr.puts "libjit not found"
  exit 1
end

check_sizeof("VALUE", "ruby.h")
check_sizeof("ID", "ruby.h")
have_func("rb_class_boot", "ruby.h")
have_func('fmemopen')

rb_files = Dir['*.rb']
rpp_files = Dir['*.rpp']
generated_files = rpp_files.map { |f| f.sub(/\.rpp$/, '') }

srcs = Dir['*.c']
generated_files.each do |f|
  if f =~ /\.c$/ then
    srcs << f
  end
end
srcs.uniq!
$objs = srcs.map { |f| f.sub(/\.c$/, ".#{$OBJEXT}") }

if Config::CONFIG['CC'] == 'gcc' then
  # $CFLAGS << ' -Wall -g -pedantic -Wno-long-long'
  $CFLAGS << ' -Wall -g'
end

create_makefile("jit")

append_to_makefile = ''

rpp_files.each do |rpp_file|
dest_file = rpp_file.sub(/\.rpp$/, '')
append_to_makefile << <<END
#{dest_file}: #{rpp_file} #{rb_files.join(' ')}
	$(RUBY) rubypp.rb #{rpp_file} #{dest_file}
END
end

generated_headers = generated_files.select { |x| x =~ /\.h$/ || x =~ /\.inc$/ }
append_to_makefile << <<END
$(OBJS): #{generated_headers.join(' ')}
clean: clean_generated_files
clean_generated_files:
	@$(RM) #{generated_files.join(' ')}

install: $(includedir)/rubyjit.h

$(includedir)/rubyjit.h: rubyjit.h
	$(INSTALL_PROG) rubyjit.h $(includedir)
END

File.open('Makefile', 'a') do |makefile|
  makefile.puts(append_to_makefile)
end

