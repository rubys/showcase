module CategoriesHelper
  def cat_extension_path(*args)
    if args.last.instance_of? Hash
      args.last[:part] = args.first.part
    else
      args += {part: args.first.part}
    end
    
    category_path(*args)
  end
end
