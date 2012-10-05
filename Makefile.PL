use ExtUtils::MakeMaker;

WriteMakefile(
	NAME          => 'R::Comment2DocDraft',
	VERSION_FROM  => 'lib/R/Comment2DocDraft.pm',
	PREREQ_PM     => {
		'English'    => 0,
		'File::Temp' => 0,
	},
	EXE_FILES    => ['bin/r-comment2docdraft'],
	AUTHOR        => 'Zuguang Gu <jokergoo@gmail.com>',
	ABSTRACT      => 'convert comments to documentaries in R script',
	LICENSE       => 'perl',
);
