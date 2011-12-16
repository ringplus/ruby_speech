require 'active_support/core_ext/class/attribute'

module RubySpeech
  module GenericElement

    def self.included(klass)
      klass.class_attribute :registered_ns, :registered_name
      klass.extend ClassMethods
    end

    module ClassMethods
      @@registrations = {}

      # Register a new stanza class to a name and/or namespace
      #
      # This registers a namespace that is used when looking
      # up the class name of the object to instantiate when a new
      # stanza is received
      #
      # @param [#to_s] name the name of the node
      #
      def register(name)
        self.registered_name = name.to_s
        self.registered_ns = namespace
        @@registrations[[self.registered_name, self.registered_ns]] = self
      end

      # Find the class to use given the name and namespace of a stanza
      #
      # @param [#to_s] name the name to lookup
      #
      # @return [Class, nil] the class appropriate for the name
      def class_from_registration(name)
        @@registrations[[name.to_s, namespace]]
      end

      # Import an XML::Node to the appropriate class
      #
      # Looks up the class the node should be then creates it based on the
      # elements of the XML::Node
      # @param [XML::Node] node the node to import
      # @return the appropriate object based on the node name and namespace
      def import(node)
        node = Nokogiri::XML.parse(node, nil, nil, Nokogiri::XML::ParseOptions::NOBLANKS).root unless node.is_a?(Nokogiri::XML::Node)
        return node.content if node.is_a?(Nokogiri::XML::Text)
        klass = class_from_registration(node.element_name)
        if klass && klass != self
          klass.import node
        else
          new.inherit node
        end
      end

      def new(element_name, atts = {}, &block)
        blk_proc = lambda do |new_node|
          atts.each_pair { |k, v| new_node.send :"#{k}=", v }
          block_return = new_node.instance_eval &block if block_given?
          new_node << new_node.encode_special_chars(block_return) if block_return.is_a?(String)
        end

        case RUBY_VERSION.split('.')[0,2].join.to_i
        when 18
          super(element_name).tap do |n|
            blk_proc[n]
          end
        else
          super(element_name) do |n|
            blk_proc[n]
          end
        end
      end
    end

    def children
      super.map { |c| self.class.import c }
    end

    def embed(other)
      case other
      when String
        self << encode_special_chars(other)
      when self.class.root_element
        other.children.each do |child|
          self << child
        end
      when self.class.module::Element
        self << other
      else
        raise ArgumentError, "Can only embed a String or an SSML element"
      end
    end

    def method_missing(method_name, *args, &block)
      const_name = method_name.to_s.sub('ssml', '').titleize.gsub(' ', '')
      const = self.class.module.const_get const_name
      if const && self.class::VALID_CHILD_TYPES.include?(const)
        if const == String
          self << encode_special_chars(args.first)
        else
          self << const.new(*args, &block)
        end
      else
        super
      end
    end

    def eql?(o, *args)
      super o, :content, :children, *args
    end
  end # Element
end # RubySpeech
