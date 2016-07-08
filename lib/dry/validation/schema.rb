require 'dry/logic/predicates'
require 'dry/types/constraints'

require 'dry/validation/predicate_registry'
require 'dry/validation/schema_compiler'
require 'dry/validation/schema/key'
require 'dry/validation/schema/value'
require 'dry/validation/schema/check'

require 'dry/validation/error'
require 'dry/validation/result'
require 'dry/validation/messages'
require 'dry/validation/error_compiler'
require 'dry/validation/hint_compiler'

require 'dry/validation/schema/deprecated'
require 'dry/validation/schema/class_interface'
require 'dry/validation/executor'

module Dry
  module Validation
    class Schema
      attr_reader :rules

      attr_reader :checks

      attr_reader :predicates

      attr_reader :input_processor

      attr_reader :rule_compiler

      attr_reader :error_compiler

      attr_reader :hint_compiler

      attr_reader :options

      attr_reader :type_map

      attr_reader :executor

      def initialize(rules, options)
        @type_map = self.class.type_map
        @predicates = options.fetch(:predicate_registry).bind(self)
        @rule_compiler = SchemaCompiler.new(predicates, options)
        @error_compiler = options.fetch(:error_compiler)
        @hint_compiler = options.fetch(:hint_compiler)
        @input_processor = options[:input_processor]

        initialize_options(options)
        initialize_rules(rules)
        initialize_checks(options.fetch(:checks, []))

        @executor = Executor.new do |steps|
          steps << ProcessInput.new(input_processor) if input_processor
          steps << ApplyRules.new(@rules)
          steps << ApplyChecks.new(@checks) if @checks.any?
          steps << BuildErrors.new(self.class.config.path)
        end

        freeze
      end

      def with(new_options)
        self.class.new(self.class.rules, options.merge(new_options))
      end

      def call(input)
        processed_input = input_processor[input]

        Result.new(
          processed_input,
          executor.(processed_input, {}),
          error_compiler,
          hint_compiler
        )
      end

      def curry(*curry_args)
        -> *args { call(*(curry_args + args)) }
      end

      def to_proc
        -> input { call(input) }
      end

      def arity
        1
      end

      def to_ast
        self.class.to_ast
      end

      private

      def initialize_options(options)
        @options = options

        self.class.options.each do |name, default|
          value = options.fetch(name) do
            case default
            when Proc then default.()
            else default end
          end

          instance_variable_set("@#{name}", value)
        end
      end

      def initialize_rules(rules)
        @rules = rules.each_with_object({}) do |rule, result|
          result[rule.name] = rule_compiler.visit(rule.to_ast)
        end
      end

      def initialize_checks(checks)
        @checks = checks.each_with_object({}) do |check, result|
          result[check.name] = rule_compiler.visit(check.to_ast)
        end
      end
    end
  end
end
