module CategoriesHelper
  def cat_extension_path(*args)
    STDERR.puts args.inspect
    if args.last.instance_of? Hash
      args.last[:part] = args.first.part
    else
      args.push(part: args.first.part)
    end
    
    category_path(*args)
  end
end
