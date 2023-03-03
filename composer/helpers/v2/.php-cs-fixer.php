<?php
$finder = PhpCsFixer\Finder::create()
    ->in(__DIR__ . '/src')
    ->in(__DIR__ . '/bin');
$config = new PhpCsFixer\Config();
return $config
    ->setRules([
        '@Symfony' => true,
        'blank_line_after_opening_tag' => true,
        'concat_space' => ['spacing' => 'one'],
        'declare_strict_types' => true,
        'increment_style' => ['style' => 'post'],
        'modernize_types_casting' => true,
        'multiline_whitespace_before_semicolons' => true,
        'no_useless_else' => true,
        'no_useless_return' => true,
        'ordered_imports' => true,
        'php_unit_construct' => true,
        'php_unit_dedicate_assert' => true,
        'phpdoc_align' => false,
        'phpdoc_order' => true,
        'single_line_comment_style' => true,
        'ternary_to_null_coalescing' => true,
        'void_return' => true,
        'yoda_style' => false,
    ])
    ->setFinder($finder)
    ->setUsingCache(true)
    ->setRiskyAllowed(true);
