require 'erbpp'

class DefineModule < ErbPP

  def initialize(erb_path,&block)
    super(nil, erb_path)
    @mod_var = "mM"
    @tmpl_dir = File.join(File.dirname(erb_path),"tmpl")
    instance_eval(&block)
  end

  attr_reader :tmpl_dir

  define_attrs %w[
    m_prefix
    mod_var
    class_name
    desc
  ]

  def class_alias(*args)
    @class_alias.concat(args)
  end

  def load_func_def(file)
    str = open(file,"r").read
    ary = eval(str)
    ary.each{|h| check_func_def(h)}
  end

  def load_const_def(file)
    str = open(file,"r").read
    ary = eval(str)
    ary.each do |name,desc|
      desc ||= ""
      value = "DBL2NUM(#{name})"
      #name.sub!(/^M_/,"")
      Const.new(self,name,value,desc)
    end
  end

end


class Argument

  def description
    @func.param_desc[@name] ||
      if @prop[:param]
        "@param [#{rb_class}] #{@name}"
      elsif @prop[:narray]
        "@param [#{na_class}] #{@name}"
      end
  end

  NUM2DATA =
    {
     "double"=>"%2 = NUM2DBL(%1)",
     "int"=>"%2 = NUM2INT(%1)",
     "unsigned int"=>"%2 = NUM2UINT(%1)",
     "size_t"=>"%2 = NUM2SIZET(%1)",
     "gsl_mode_t"=>"%2 = NUM2INT(%1)",
     "gsl_sf_legendre_t"=>"%2 = NUM2INT(%1)",
     "gsl_sf_mathieu_workspace *"=>'
    if (rb_obj_is_kind_of(%1,cWorkspace)!=Qtrue) {
        rb_raise(rb_eTypeError,"last argument must be "
                 "Numo::GSL::Sf::MathieuWorkspace class");
    }
    TypedData_Get_Struct(%1, gsl_sf_mathieu_workspace, &mathieuws_type, %2)'
    }

  DATA2NUM =
    {
     "double"=>"DBL2NUM(%1)",
     "int"=>"INT2NUM(%1)",
     "unsigned int"=>"UINT2NUM(%1)",
     "size_t"=>"SIZET2NUM(%1)",
     "gsl_sf_result *"=>["DBL2NUM(%1.val)","DBL2NUM(%1.err)"]
    }

  TYPEMAP =
    {
     "double"=>"cDF",
     "unsigned int"=>"cUI",
     "int"=>"cI",
     "size_t"=>"cSZ"
    }

  NACLASSMAP =
    {
     "double"=>"Numo::DFloat",
     "unsigned int"=>"Numo::UInt32",
     "int"=>"Numo::Int32",
     "size_t"=>"Numo::UInt64",
     "gsl_sf_result *"=>["Numo::DFloat"]*2,
     "gsl_sf_result_e10 *"=>["Numo::DFloat"]*2+["Numo::Int32"],
     "gsl_sf_mathieu_workspace *"=>"Numo::GSL::Sf::MathieuWorkspace"
    }

  RBCLASSMAP =
    {
     "double"=>"Float",
     "unsigned int"=>"Integer",
     "int"=>"Integer",
     "size_t"=>"Integer",
     "gsl_mode_t"=>"Integer"
    }

  CTYPEMAP =
    {
     "double"=>"double",
     "unsigned int"=>"uint32_t",
     "int"=>"int32_t",
     "size_t"=>"uint64_t"
    }

  RETNAMEMAP =
    {
     "double"=>"Numo::DFloat",
     "unsigned int"=>"Numo::UInt32",
     "int"=>"Numo::Int32",
     "size_t"=>"Numo::UInt64",
     "gsl_sf_result *"=>["Numo::DFloat"]*2,
     "gsl_sf_result_e10 *"=>["Numo::DFloat"]*2+["Numo::Int32"]
    }

  def initialize(func,idx,type,name,prop)
    @func = func
    @idx  = idx
    @type = type
    @name = name
    @prop = prop
    @pass = @prop[:pass]

    if /(.+)\*$/ =~ @type
      @type2 = $1.strip
    end

    if @prop[:output]
      @n_out =
        case @type
        when "gsl_sf_result_e10 *"
          3
        when "gsl_sf_result *"
          2
        else
          1
        end
    end

    @ctype = CTYPEMAP[@type] || CTYPEMAP[@type2]
  end

  attr_reader :type, :name
  attr_reader :pass, :n_out

  [:input,:output,:param,:narray].each do |sym|
    define_method(sym){@prop[sym]}
  end

  def c_var
    "c#{@idx}"
  end

  def c_arg
    (@pass == :pointer) ? "&"+c_var : c_var
  end

  def v_var
    if @func.varg
      "v[#{@idx}]"
    else
      "v#{@idx}"
    end
  end

  def ain_def
    "{#{na_type},0}"
  end

  def aout_def
    case @type
    when "gsl_sf_result_e10 *"
      return "{cDF,0},{cDF,0},{cI,0}"
    when "gsl_sf_result *"
      return "{cDF,0},{cDF,0}"
    end
    case @pass
    when :array
      "{#{na_type},1,shape}"
    when :pointer,:return
      "{#{na_type},0}"
    else
      raise "no aout_def for #{self.inspect}"
    end
  end

  def na_type
    TYPEMAP[@type] || TYPEMAP[@type2]
  end

  def na_class
    NACLASSMAP[@type] || NACLASSMAP[@type2]
  end

  def rb_class
    RBCLASSMAP[@type] || RBCLASSMAP[@type2]
  end

  def ret_val
    case @type
    when "gsl_sf_result *"
      [@name+".val",@name+".err"]
    when "gsl_sf_result_e10 *"
      [@name+".val",@name+".err",@name+".e10"]
    else
      @name
    end
  end

  def def_var
    if @prop[:param]
      "#{@type} #{c_var};"
    elsif @prop[:input]
      "#{@type} #{c_var};"
    elsif @pass == :array
      "#{@type} *#{c_var};"
    elsif @pass == :pointer
      "#{@type2} #{c_var};"
    elsif @pass == :return
      "#{@type} #{c_var};"
    else
      raise "no variable definition"
    end
  end

  def def_value
    "VALUE #{v_var};"
  end

  def set_value
    NUM2DATA[@type].gsub(/%1/,v_var).sub(/%2/,c_var)+";"
  end

  def get_value
    case a = DATA2NUM[@type]
    when String
      a.gsub(/%1/,c_var)
    when Array
      a.map{|s| s.gsub(/%1/,c_var)}
    end
  end

  def store_to_array(va)
    a = get_value
    a = [a] unless Array === a
    a.map{|x|"rb_ary_push(#{va},#{x});"}.join("\n"+" "*8)
  end

  def set_param(opt)
    n = @func.n_input
    if @type == "gsl_mode_t" && n == @idx+1
      return <<EOL
    if (argc==#{@idx}) {
        #{c_var} = GSL_MODE_DEFAULT;
    } else if (argc==#{@idx+1}) {
        #{set_value}
    } else {
        rb_raise(rb_eArgError,"invalid number of argument: %d for #{n-1} or #{n}",argc);
    }
    #{opt} = &#{c_var}; //#{@name}
EOL
    else
      return <<EOL
    #{set_value}
    #{opt} = &#{c_var}; //#{@name}
EOL
    end
  end

  def get_param(opt)
    "#{c_var} = *(#{@type}*)(#{opt}); //#{@name}"
  end

  def get_data(lp)
    "#{c_var} = *(#{@ctype}*)GET_PTR(#{lp},#{cnt}); //#{@name}"
  end

  def get_ptr(lp)
    if @pass == :array
      "#{c_var} = (#{@ctype}*)GET_PTR(#{lp},#{cnt}); //#{@name}"
    end
  end

  def set_data(lp)
    if @pass != :array
      if "gsl_sf_result_e10 *" == @type
        "*(double*)GET_PTR(#{lp},#{cnt}) = #{c_var}.val; "+
        "*(double*)GET_PTR(#{lp},#{cnt}) = #{c_var}.err; "+
        "*(int32_t*)GET_PTR(#{lp},#{cnt}) = #{c_var}.e10; //#{@name}"
      elsif "gsl_sf_result *" == @type
        "*(double*)GET_PTR(#{lp},#{cnt}) = #{c_var}.val; "+
        "*(double*)GET_PTR(#{lp},#{cnt}) = #{c_var}.err; //#{@name}"
      else
        "*(#{@ctype}*)GET_PTR(#{lp},#{cnt}) = #{c_var}; //#{@name}"
      end
    end
  end

  def cnt
    @func.counter.inc
  end
end

#----------------------------------------------------------

class Counter
  def initialize
    @i = 0
  end
  def inc
    i = @i
    @i += 1
    i
  end
end

#----------------------------------------------------------

class GslFunction < Function

  def self.lookup(h)
    false
  end

  PARAM_DESC = {}
  PARAM_NAMES = {}

  def param_desc
    self.class::PARAM_DESC
  end

  def desc_param
    t = (["Numo::DFloat"]*n_out).join(",")
    t = @args_out.map{|a| a.na_class}.flatten.join(", ")
    v = @args_out.map{|a| a.ret_val}.flatten.join(", ")
    if n_out > 1
      r = "@return [[#{t}]]  array of [#{v}]"
    else
      r = "@return [#{t}]  #{v}"
    end
    @args_input.map{|a| a.description}+[r]
  end


  def param_names
    self.class::PARAM_NAMES
  end

  def is_param(tp,nm)
    #$stderr.puts "type='#{tp}' name='#{nm}'"
    a = self.class::PARAM_NAMES[tp]
    case a
    when Array
      a.include?(nm)
    else
      a
    end
  end

  def parse_args(h)
    i = 0
    @parsed_args = []
    h[:args].each do |type,name|
      type = type.sub(/^const\s+/,"").strip
      if /_array$/ =~ name && /(.+)\*$/ =~ type
        type = $1.strip
        name = name+"[]"
      end
      prop = argument_property(type,name)
      @parsed_args << Argument.new(self,i,type,name,prop)
      i += 1
    end
    t = h[:func_type]
    if t != "void"
      prop = argument_property(t,"return")
      @parsed_args << Argument.new(self,i,t,"return",prop)
    end
  end

  def argument_property(type,name)
    if name == "return"
      {output:true, narray:true, pass: :return}
    elsif /\[\]$/ =~ name
      {output:true, narray:true, pass: :array}
    elsif is_param(type,name)
      {input:true, param:true}
    elsif /\*$/ =~ type
      {output:true, narray:true, pass: :pointer}
    else
      {input:true, narray:true}
    end
  end

  def initialize(parent,tmpl,**h)
    parse_args(h)
    @args_param = @parsed_args.select{|a|a.param}
    @args_input = @parsed_args.select{|a|a.input}
    @args_in = @parsed_args.select{|a|a.narray && a.input}
    @args_out = @parsed_args.select{|a|a.narray && a.output}
    if @args_param.any?{|a| a.type=="gsl_mode_t"}
      @varg = -1
      n_arg(-1)
    else
      @varg = nil
      n_arg(@args_param.size+@args_in.size)
    end
    @parsed_args.each do |a|
      if a.pass == :array
        @generate_array = true
        break
      end
    end
    h[:singleton] = true
    super(parent,tmpl,**h)
    @counter = Counter.new
  end

  #attr_reader :name
  attr_reader :args_out, :args_in, :args_param, :varg
  attr_reader :generate_array

  def n_param
    @args_param.size
  end

  def n_in
    @args_in.size
  end

  def n_input
    @args_input.size
  end

  def n_out
    n = 0
    @args_out.each{|a| n+=a.n_out}
    n
  end

  def def_ain
    @args_in.map{|a| a.ain_def}.join(",")
  end

  def def_aout
    @args_out.map{|a| a.aout_def}.join(",")
  end

  def find_name(name)
    @parsed_args.find{|a| a.name==name}
  end

  def c_args
    @parsed_args.select{|a| a.pass != :return}.
      map{|a| a.c_arg}.join(",")
  end

  def recv
    a = args_out.last
    if a && a.pass == :return
      a.c_var + " = "
    else
      ""
    end
  end

  def method_args
    s = @args_input.map{|a| a.name}.join(",")
    s.sub(/,mode$/,",[mode]")
  end

  def cdef_args
    if @varg
      "int argc, VALUE *v, VALUE mod"
    else
      "VALUE mod," +
        @args_input.map{|a|"VALUE #{a.v_var}"}.join(",")
    end
  end

  def ndl_args
    @args_in.map{|a| a.v_var}.join(",")
  end

end
