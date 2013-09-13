#!/bin/bash -e

# Script to run TopHat program
# It takes comma-seprated list of files containing short sequence reads in fasta or fastq format and bowtie index files as input.
# It produces output files: read alignments in .bam format and other files.
# author: Chikako Ragan, Denis Bauer
# date: Jan. 2011
# modified by Fabian Buske and Hugh French
# date: 2013-


# messages to look out for -- relevant for the QC.sh script:
# QCVARIABLES,truncated file

echo ">>>>> readmapping with Tophat "
echo ">>>>> startdate "`date`
echo ">>>>> hostname "`hostname`
echo ">>>>> job_name "$JOB_NAME
echo ">>>>> job_id "$JOB_ID
echo ">>>>> $(basename $0) $*"


function usage {
echo -e "usage: $(basename $0) -k NGSANE -f FASTA -r REFERENCE -o OUTDIR [OPTIONS]

Script running read mapping for single and paired DNA reads from fastq files
It expects a fastq file, pairdend, reference genome  as input and 
It runs tophat, converts the output to .bam files, adds header information and
writes the coverage information for IGV.

required:
  -k | --toolkit <path>     location of the NGSANE repository 
  -f | --fastq <file>       fastq file
  -r | --reference <file>   reference genome
  -o | --outdir <path>      output dir

options:
  -i | --rgid <name>        read group identifier RD ID (default: exp)
  -l | --rglb <name>        read group library RD LB (default: qbi)
  -p | --rgpl <name>        read group platform RD PL (default: illumna)
  -s | --rgsi <name>        read group sample RG SM prefac (default: )
  -R | --region <ps>        region of specific interest, e.g. targeted reseq
                             format chr:pos-pos
  --forceSingle             run single end eventhough second read is present
"
exit
}

if [ ! $# -gt 3 ]; then usage ; fi

#DEFAULTS
FORCESINGLE=0

#INPUTS
while [ "$1" != "" ]; do
	case $1 in
	-k | toolkit )          shift; CONFIG=$1 ;; # ENSURE NO VARIABLE NAMES FROM CONFIG
	-f | --fastq )          shift; f=$1 ;; # fastq file
	-r | --reference )      shift; FASTA=$1 ;; # reference genome
	-o | --outdir )         shift; OUTDIR=$1 ;; # output dir
	-a | --annot )          shift; REFSEQGTF=$1 ;; # refseq annotation
	
	-l | --rglb )           shift; LIBRARY=$1 ;; # read group library RD LB
	-p | --rgpl )           shift; PLATFORM=$1 ;; # read group platform RD PL
	-s | --rgsi )           shift; SAMPLEID=$1 ;; # read group sample RG SM (pre)
	-R | --region )         shift; SEQREG=$1 ;; # (optional) region of specific interest, e.g. targeted reseq
	
	--forceSingle )         FORCESINGLE=1;;

    --recover-from )        shift; RECOVERFROM=$1 ;; # attempt to recover from log file
	-h | --help )           usage ;;
	* )                     echo "dont understand $1"
	esac
	shift
done


#PROGRAMS (note, both configs are necessary to overwrite the default, here:e.g.  TASKTOPHAT)
. $CONFIG
. ${NGSANE_BASE}/conf/header.sh
. $CONFIG

################################################################################
CHECKPOINT="programs"

for MODULE in $MODULE_TOPHATCUFF; do module load $MODULE; done  # save way to load modules that itself load other modules
export PATH=$PATH_TOPHATCUFF:$PATH
module list
echo "PATH=$PATH"
#this is to get the full path (modules should work but for path we need the full path and this is the\
# best common denominator)
PATH_IGVTOOLS=$(dirname $(which igvtools.jar))
PATH_PICARD=$(dirname $(which MarkDuplicates.jar))
PATH_RNASEQC=$(dirname $(which RNA-SeQC.jar))

echo "[NOTE] set java parameters"
JAVAPARAMS="-Xmx"$(python -c "print int($MEMORY_TOPHAT*0.8)")"g -Djava.io.tmpdir="$TMP"  -XX:ConcGCThreads=1 -XX:ParallelGCThreads=1" 
unset _JAVA_OPTIONS
echo "JAVAPARAMS "$JAVAPARAMS

echo -e "--NGSANE      --\n" $(trigger.sh -v 2>&1)
echo -e "--JAVA        --\n" $(java -Xmx=200m -version 2>&1)
[ -z "$(which java)" ] && echo "[ERROR] no java detected" && exit 1
echo -e "--tophat2     --\n "$(tophat --version)
[ -z "$(which tophat)" ] && echo "[ERROR] no tophat detected" && exit 1
echo -e "--cufflinks   --\n "$(cufflinks 2>&1 | head -n 2 )
[ -z "$(which cufflinks)" ] && echo "[ERROR] no cufflinks detected" && exit 1
echo -e "--bowtie2     --\n "$(bowtie2 --version)
[ -z "$(which bowtie2)" ] && echo "[ERROR] no bowtie2 detected" && exit 1
echo -e "--samtools    --\n "$(samtools 2>&1 | head -n 3 | tail -n-2)
[ -z "$(which samtools)" ] && echo "[ERROR] no samtools detected" && exit 1
echo -e "--R           --\n "$(R --version | head -n 3)
[ -z "$(which R)" ] && echo "[ERROR] no R detected" && exit 1
echo -e "--igvtools    --\n "$(java -jar $JAVAPARAMS $PATH_IGVTOOLS/igvtools.jar version 2>&1)
[ ! -f $PATH_IGVTOOLS/igvtools.jar ] && echo "[ERROR] no igvtools detected" && exit 1
echo -e "--picard      --\n "$(java -jar $JAVAPARAMS $PATH_PICARD/MarkDuplicates.jar --version 2>&1)
[ ! -f $PATH_PICARD/MarkDuplicates.jar ] && echo "[ERROR] no picard detected" && exit 1
echo -e "--samstat     --\n "$(samstat -h | head -n 2 | tail -n1)
[ -z "$(which samstat)" ] && echo "[ERROR] no samstat detected" && exit 1
echo -e "--bedtools    --\n "$(bedtools --version)
[ -z "$(which bedtools)" ] && echo "[ERROR] no bedtools detected" && exit 1
echo -e "--htSeq       --\n "$(htseq-count | tail -n 1)
[ -z "$(which htseq-count)" ] && [ -n "$GENCODEGTF" ] && echo "[ERROR] no htseq-count or GENCODEGTF detected" && exit 1
echo -e "--RNA-SeQC    --\n "$(java -jar $JAVAPARAMS ${PATH_RNASEQC}/RNA-SeQC.jar --version  2>&1 | head -n 1 )
[ -z "$(which RNA-SeQC.jar)" ] && echo "[ERROR] no RNA_SeQC.jar detected" && exit 1


echo -e "\n********* $CHECKPOINT\n"
################################################################################
CHECKPOINT="parameters"

# get basename of f (samplename)
n=${f##*/}

# get info about input file
FASTASUFFIX=${FASTA##*.}
BAMFILE=$OUTDIR/../${n/%$READONE.$FASTQ/.$ASD.bam}

CUFOUT=${OUTDIR/$TASKTOPHAT/$TASKCUFF}

#remove old files
if [ -z "$RECOVERFROM" ]; then
    if [ -d $OUTDIR ]; then rm -r $OUTDIR; fi
    if [ -d $CUFOUT ]; then rm -r $CUFOUT; fi
fi


if [ "$f" != "${f/$READONE/$READTWO}" ] && [ -e ${f/$READONE/$READTWO} ] && [ "$FORCESINGLE" = 0 ]; then
    PAIRED="1"
    f2=${f/$READONE/$READTWO}
    echo "[NOTE] Paired library detected"
else
    PAIRED="0"
    echo "[NOTE] Single-Strand (unpaired) library detected"
fi

## is ziped ?
ZCAT="cat" # always cat
if [[ $f = *.gz ]]; then # unless its zipped
    ZCAT="zcat";
fi


## GTF provided?
if [ -n "$GENCODEGTF" ]; then
    echo "[NOTE] Gencode GTF: $GENCODEGTF"
    if [ ! -f $GENCODEGTF ]; then
        echo "[ERROR] GENCODE GTF specified but not found!"
        exit 1
    fi 
elif [ -n "$REFSEQGTF" ]; then
    echo "[NOTE] Refseq GTF: $REFSEQGTF"
    if [ ! -f $REFSEQGTF ]; then
        echo "[ERROR] REFSEQ GTF specified but not found!"
        exit 1
    fi
fi

if [ -n "$REFSEQGTF" ] && [ -n "$GENCODEGTF" ]; then
    echo "[WARN] GENCODE and REFSEQ GTF found. GENCODE takes preference."
fi
if [ ! -z "$DOCTOREDGTFSUFFIX" ]; then
    if [ ! -f ${GENCODEGTF/%.gtf/$DOCTOREDGTFSUFFIX} ] ; then
        echo "[ERROR] Doctored GTF suffix specified but gtf not found: ${GENCODEGTF/%.gtf/$DOCTOREDGTFSUFFIX}"
        exit 1
    else 
        echo "[NOTE] Doctored GTF: ${GENCODEGTF/%.gtf/$DOCTOREDGTFSUFFIX}"
    fi
fi

# check library info is set
if [ -z "$RNA_SEQ_LIBRARY_TYPE" ]; then
    echo "[ERROR] RNAseq library type not set (RNA_SEQ_LIBRARY_TYPE): either fr-unstranded or fr-firststrand"
    exit 1;
else
    echo "[NOTE] RNAseq library type: $RNA_SEQ_LIBRARY_TYPE"
fi
if [[ -z "$EXPID" || -z "$LIBRARY" || -z "$PLATFORM" ]]; then
    echo "[ERROR] library info not set (EXPID, LIBRARY, and PLATFORM): free text needed"
    exit 1;
else
    echo "[NOTE] EXPID $EXPID; LIBRARY $LIBRARY; PLATFORM $PLATFORM"
fi

mkdir -p $OUTDIR

echo -e "\n********* $CHECKPOINT\n"
################################################################################
CHECKPOINT="recall files from tape"

if [ -n "$DMGET" ]; then
    dmget -a $(dirname $FASTA)/*
    dmget -a ${f/$READONE/"*"}
fi

echo -e "\n********* $CHECKPOINT\n"
################################################################################
CHECKPOINT="run tophat"

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 

    echo "[NOTE] tophat $(date)"
    ## generating the index files
    if [ ! -e ${FASTA/.${FASTASUFFIX}/}.1.bt2 ]; then echo ">>>>> make .bt2"; bowtie2-build $FASTA ${FASTA/.${FASTASUFFIX}/}; fi
    if [ ! -e $FASTA.fai ]; then echo ">>>>> make .fai"; samtools faidx $FASTA; fi
    
    RUN_COMMAND="tophat $TOPHATADDPARAM --keep-fasta-order --num-threads $CPU_TOPHAT --library-type $RNA_SEQ_LIBRARY_TYPE --rg-id $EXPID --rg-sample $PLATFORM --rg-library $LIBRARY --output-dir $OUTDIR ${FASTA/.${FASTASUFFIX}/} $f $f2"
    echo $RUN_COMMAND && eval $RUN_COMMAND
    echo "[NOTE] tophat end $(date)"

    # mark checkpoint
    [ -d $OUTDIR ] && echo -e "\n********* $CHECKPOINT\n" && unset RECOVERFROM
fi 

################################################################################
CHECKPOINT="merge mapped and unmapped"

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 

    echo "[NOTE] samtools merge"
    samtools merge -f $BAMFILE.tmp.bam $OUTDIR/accepted_hits.bam $OUTDIR/unmapped.bam
    
    if [ "$PAIRED" = "1" ]; then
        # fix mate pairs
        echo "[NOTE] samtools fixmate"
        samtools sort -n $BAMFILE.tmp.bam $BAMFILE.tmp2
        samtools fixmate $BAMFILE.tmp2.bam $BAMFILE.tmp.bam
        rm $BAMFILE.tmp2.bam
    fi
    
    echo "[NOTE] samtools sort"
    samtools sort $BAMFILE.tmp.bam ${BAMFILE/.bam/.samtools}
    rm $BAMFILE.tmp.bam
    
    echo "[NOTE] add read group"
    THISTMP=$TMP/$n$RANDOM #mk tmp dir because picard writes none-unique files
    mkdir -p  $THISTMP
    RUN_COMMAND="java $JAVAPARAMS -jar $PATH_PICARD/AddOrReplaceReadGroups.jar \
         I=${BAMFILE/.bam/.samtools}.bam \
         O=$BAMFILE \
         LB=$EXPID PL=Illumina PU=XXXXXX SM=$EXPID \
         VALIDATION_STRINGENCY=SILENT \
        TMP_DIR=$THISTMP"
    echo $RUN_COMMAND && eval $RUN_COMMAND
    rm -r $THISTMP
    rm ${BAMFILE/.bam/.samtools}.bam

    # mark checkpoint
    [ -f $BAMFILE ] && echo -e "\n********* $CHECKPOINT\n" && unset RECOVERFROM
fi 

################################################################################
CHECKPOINT="flagstat"

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 
    echo "[NOTE] samtools flagstat"
    samtools flagstat $BAMFILE > $BAMFILE.stats
    READ1=$($ZCAT $f | wc -l | gawk '{print int($1/4)}' )
    FASTQREADS=$READ1
    if [ -n "$f2" ]; then 
        READ2=$($ZCAT $f2 | wc -l | gawk '{print int($1/4)}' );
        let FASTQREADS=$READ1+$READ2
    fi
    echo $FASTQREADS" fastq reads" >> $BAMFILE.stats
    JUNCTION=$(wc -l $OUTDIR/junctions.bed | cut -d' ' -f 1)
    echo $JUNCTION" junction reads" >> $BAMFILE.stats
    ## get junction genes overlapping exons +-200bp
    
    if [ -n "$GENCODEGTF" ]; then
        JUNCTGENE=$(windowBed -a $OUTDIR/junctions.bed -b $GENCODEGTF -u -w 200 | wc -l | cut -d' ' -f 1)
        echo $JUNCTGENE" junction reads Gencode" >> $BAMFILE.stats
    elif [ -n "$REFSEQGTF" ]; then
        JUNCTGENE=$(windowBed -a $OUTDIR/junctions.bed -b $REFSEQGTF -u -w 200 | wc -l | cut -d' ' -f 1)
        echo $JUNCTGENE" junction reads NCBIM37" >> $BAMFILE.stats
    else 
        echo "0 junction reads (no gtf given)" >> $BAMFILE.stats
    fi

    # mark checkpoint
    [ -f $BAMFILE.stats ] && echo -e "\n********* $CHECKPOINT\n" && unset RECOVERFROM
fi 

################################################################################
CHECKPOINT="index and calculate inner distance"

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 

    echo "[NOTE] samtools index"
    samtools index $BAMFILE

    echo "********* calculate inner distance"
    echo "[NOTE] picard CollectMultipleMetrics"
    if [ ! -e $OUTDIR/../metrices ]; then mkdir $OUTDIR/../metrices ; fi
    THISTMP=$TMP/$n$RANDOM #mk tmp dir because picard writes none-unique files
    mkdir -p  $THISTMP
    RUN_COMMAND="java $JAVAPARAMS -jar $PATH_PICARD/CollectMultipleMetrics.jar \
        INPUT=$BAMFILE \
        REFERENCE_SEQUENCE=$FASTA \
        OUTPUT=$OUTDIR/../metrices/$(basename $BAMFILE) \
        VALIDATION_STRINGENCY=SILENT \
        PROGRAM=CollectAlignmentSummaryMetrics \
        PROGRAM=CollectInsertSizeMetrics \
        PROGRAM=QualityScoreDistribution \
        TMP_DIR=$THISTMP"
    echo $RUN_COMMAND && eval $RUN_COMMAND
    
    for im in $( ls $OUTDIR/../metrices/$(basename $BAMFILE)*.pdf ); do
        convert $im ${im/pdf/jpg}
    done
    rm -r $THISTMP
   
    # mark checkpoint
    [ -f $OUTDIR/../metrices/${BAMFILE##*/}.alignment_summary_metrics ] && echo -e "\n********* $CHECKPOINT\n" && unset RECOVERFROM
fi 

################################################################################
CHECKPOINT="coverage track"    

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 

    echo "[NOTE] igvtools"
    java $JAVAPARAMS -jar $PATH_IGVTOOLS/igvtools.jar count $BAMFILE \
        $BAMFILE.cov.tdf ${FASTA/$FASTASUFFIX/}genome

    # mark checkpoint
    [ -f $BAMFILE.cov.tdf ] && echo -e "\n********* $CHECKPOINT\n" && unset RECOVERFROM
fi

################################################################################
CHECKPOINT="samstat"    

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 

    echo "[NOTE] samstat"
    samstat $BAMFILE
  
    # mark checkpoint
    [ -f $BAMFILE.stats ] && echo -e "\n********* $CHECKPOINT\n" && unset RECOVERFROM    
fi

################################################################################
CHECKPOINT="samstat"    

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 

    echo "[NOTE] extract mapped reads"
    if [ "$PAIRED" = "1" ]; then
        samtools view -f 3 -b $BAMFILE > ${BAMFILE/.$ASD/.$ALN}
    else
        samtools view -F 4 -b $BAMFILE > ${BAMFILE/.$ASD/.$ALN}
    fi
    samtools index ${BAMFILE/.$ASD/.$ALN}

    # mark checkpoint
    [ -f ${BAMFILE/.$ASD/.$ALN} ] && echo -e "\n********* $CHECKPOINT\n" && unset RECOVERFROM    
fi

################################################################################
CHECKPOINT="RNA-SeQC"    

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 
    
    if [ -n "$GENCODEGTF" ]; then 
        RNASEQC_GTF=$GENCODEGTF
    elif [ -n "$REFSEQGTF" ]; then
        RNASEQC_GTF=$REFSEQGTF
    fi
    # take doctored GTF if available
    if [ -n "$DOCTOREDGTFSUFFIX" ]; then RNASEQC_GTF=${RNASEQC_GTF/%.gtf/$DOCTOREDGTFSUFFIX}; fi
    # run GC stratification if available
    RNASEQC_CG=
    if [ -f ${RNASEQC_GTF}.gc ]; then RNASEQC_CG="-strat gc -gc ${RNASEQC_GTF}.gc"; fi
    # add parameter flag
    if [ -z "$RNASEQC_GTF" ]; then
        echo "[NOTE] no GTF file specified, skipping RNA-SeQC"
    else
        RNASeQCDIR=$OUTDIR/../${n/%$READONE.$FASTQ/_RNASeQC}
        mkdir -p $RNASeQCDIR
    
        RUN_COMMAND="java $JAVAPARAMS -jar ${PATH_RNASEQC}/RNA-SeQC.jar $RNASEQCADDPARAM -n 1000 -s '${n/%$READONE.$FASTQ/}|${BAMFILE/.$ASD/.$ALN}|${n/%$READONE.$FASTQ/}' -t ${RNASEQC_GTF}  -r ${FASTA} -o $RNASeQCDIR/ $RNASEQC_CG"
        echo $RUN_COMMAND && eval $RUN_COMMAND
    
        #tar czf ${n/%$READONE.$FASTQ/_RNASeQC}.tar.gz $RNASeQCDIR 
        [ -e ${BAMFILE/.$ASD/.$ALN} ] && rm ${BAMFILE/.$ASD/.$ALN}
    fi

    # mark checkpoint
    [ -d $RNASeQCDIR ] && echo -e "\n********* $CHECKPOINT\n" && unset RECOVERFROM    
fi

################################################################################
CHECKPOINT="cufflinks"    

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 
    echo ">>>>> from $BAMFILE to $CUFOUT"
    echo "[NOTE] cufflinks $(date)"
    #specify REFSEQ or Gencode GTF depending on analysis desired.
    ## add GTF file if present
    if [ -n "$GENCODEGTF" ]; then 
        RUN_COMMAND="cufflinks --quiet $CUFFLINKSADDPARAM --GTF-guide $GENCODEGTF -p $CPU_TOPHAT --library-type $RNA_SEQ_LIBRARY_TYPE -o $CUFOUT $BAMFILE"
    elif [ -n "$REFSEQGTF" ]; then 
        RUN_COMMAND="cufflinks --quiet $CUFFLINKSADDPARAM --GTF-guide $REFSEQGTF -p $CPU_TOPHAT --library-type $RNA_SEQ_LIBRARY_TYPE -o $CUFOUT $BAMFILE"
    else
        # non reference guided
        echo "[NOTE] non reference guided run (neither GENCODEGTF nor REFSEQGTF defined)"
        RUN_COMMAND="cufflinks --quiet $CUFFLINKSADDPARAM --frag-bias-correct $FASTA -p $CPU_TOPHAT --library-type $RNA_SEQ_LIBRARY_TYPE -o $CUFOUT $BAMFILE"
    fi
    echo $RUN_COMMAND && eval $RUN_COMMAND

    # mark checkpoint
    [ -d $CUFOUT ] && echo -e "\n********* $CHECKPOINT\n" && unset RECOVERFROM    
fi
echo "[NOTE] cufflinks end $(date)"

################################################################################
echo ">>>>> alignment with TopHat - FINISHED"


################################################################################
################################################################################
################################################################################
#
# Experimental section (htseqcount)
#
################################################################################
################################################################################
################################################################################

# add Gencode GTF if present 
if [ -n "$RUNEXPERIMENTAL_HTSEQCOUNT" ] && [ -n "$GENCODEGTF" ]; then 
    ################################################################################
    CHECKPOINT="run htseq-count"    
    if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
        echo "::::::::: passed $CHECKPOINT"
    else 
    	##add secondstrand
    	
    	annoF=${GENCODEGTF##*/}
    #	echo ${annoF}
    	anno_version=${annoF%.*}
    	
    	HTOUTDIR=$OUTDIR/../${n/%$READONE.$FASTQ/_htseq_count}
    #	echo ${HTOUTDIR}
    	mkdir -p $HTOUTDIR
    
    	if [ "$RNA_SEQ_LIBRARY_TYPE" = "fr-unstranded" ]; then
    	       echo "[NOTE] library is fr-unstranded; do not run htseq-count stranded"
    	       HT_SEQ_OPTIONS="--stranded=no"
    	elif [ "$RNA_SEQ_LIBRARY_TYPE" = "fr-firststrand" ]; then
    	       echo "[NOTE] library is fr-firststrand; run htseq-count stranded"
    	       HT_SEQ_OPTIONS="--stranded=reverse"
    	elif [ "$RNA_SEQ_LIBRARY_TYPE" = "fr-secondstrand" ]; then
    	       echo "[NOTE] library is fr-secondstrand; run htseq-count stranded"
    	       HT_SEQ_OPTIONS="--stranded=yes"
    	fi
    
    	## htseq-count 
    
    	samtools sort -n $OUTDIR/accepted_hits.bam $OUTDIR/accepted_hits_sorted.tmp
    	samtools fixmate $OUTDIR/accepted_hits_sorted.tmp.bam $OUTDIR/accepted_hits_sorted.bam
    	rm $OUTDIR/accepted_hits_sorted.tmp.bam
    
    	samtools view $OUTDIR/accepted_hits_sorted.bam -f 3 | htseq-count --quiet $HT_SEQ_OPTIONS - $GENCODEGTF | grep ENSG > $HTOUTDIR/${anno_version}.gene
    	samtools view $OUTDIR/accepted_hits_sorted.bam -f 3 | htseq-count --quiet --mode=intersection-strict $HT_SEQ_OPTIONS - $GENCODEGTF | grep ENSG > $HTOUTDIR/${anno_version}_strict.gene
    	samtools view $OUTDIR/accepted_hits_sorted.bam -f 3 | htseq-count --quiet --mode=intersection-nonempty $HT_SEQ_OPTIONS - $GENCODEGTF | grep ENSG > $HTOUTDIR/${anno_version}_nonempty.gene
    #	samtools view $OUTDIR/accepted_hits_sorted.bam  | htseq-count --quiet --idattr="transcript_id" $HT_SEQ_OPTIONS - $GENCODEGTF | grep ENST > $HTOUTDIR/${anno_version}.transcript
        
        # mark checkpoint
        [ -f $HTOUTDIR/${anno_version}.gene ] && echo -e "\n********* $CHECKPOINT\n" && unset RECOVERFROM    
    fi
    
    ################################################################################
    CHECKPOINT="Create bigwigs"    
    if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
        echo "::::::::: passed $CHECKPOINT"
    else 
    
        if [ $RNA_SEQ_LIBRARY_TYPE = "fr-unstranded" ]; then
    	    echo "[NOTE] make bigwigs; library is fr-unstranded "
    	    BAM2BW_OPTION_1="FALSE"
    	    BAM2BW_OPTION_2="FALSE"
        elif [ $RNA_SEQ_LIBRARY_TYPE = "fr-firststrand" ]; then
    	    echo "[NOTE] make bigwigs; library is fr-firststrand "
    	    BAM2BW_OPTION_1="TRUE"
    	    BAM2BW_OPTION_2="TRUE"
        elif [ $RNA_SEQ_LIBRARY_TYPE = "fr-secondstrand" ]; then
    	    echo "[NOTE] make bigwigs; library is fr-secondstrand "
    	    BAM2BW_OPTION_1="TRUE"
    	    BAM2BW_OPTION_2="FALSE"	    
        fi
    
        BIGWIGSDIR=$OUTDIR/../
    
    	#make a paired only (f -3 ) bam so bigwigs are comparable to counts.
    	samtools view -f 3 -h -b $OUTDIR/accepted_hits.bam > $OUTDIR/accepted_hits_f3.bam
    	
        #file_arg sample_arg stranded_arg firststrand_arg paired_arg
        Rscript --vanilla ${NGSANE_BASE}/tools/BamToBw.R $OUTDIR/accepted_hits_f3.bam ${n/%$READONE.$FASTQ/} $BAM2BW_OPTION_1 $BIGWIGSDIR $BAM2BW_OPTION_2
    	
    	# index accepted_hits.bam
    	samtools index $OUTDIR/accepted_hits.bam
    
        # mark checkpoint
        [ -f ${n/%$READONE.$FASTQ/.bw} ] && echo -e "\n********* $CHECKPOINT\n" && unset RECOVERFROM    
    fi
    	
    ################################################################################
    CHECKPOINT="calculate RPKMs per Gencode Gene"    
    if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
        echo "::::::::: passed $CHECKPOINT"
    else 
        echo "[NOTE] Gencode RPKM calculation"
    
        RPKMSSDIR=$OUTDIR/../
    	
        Rscript --vanilla ${NGSANE_BASE}/tools/CalcGencodeGeneRPKM.R $GENCODEGTF $HTOUTDIR/${anno_version}.gene $RPKMSSDIR/${n/%$READONE.$FASTQ/_gene} ${anno_version}
    
        echo "[NOTE] Gencode RPKM calculation - FINISHED"
        echo "[NOTE] Create filtered bamfile"
    	
        ##remove r_RNA and create counts.
    	python ${NGSANE_BASE}/tools/extractFeature.py -f $GENCODEGTF --keep rRNA Mt_tRNA Mt_rRNA tRNA rRNA_pseudogene tRNA_pseudogene Mt_tRNA_pseudogene Mt_rRNA_pseudogene > $OUTDIR/mask.gff
    	python ${NGSANE_BASE}/tools/extractFeature.py -f $GENCODEGTF --keep RNA18S5 RNA28S5 -l 17 >> $OUTDIR/mask.gff
    	        
        intersectBed -v -abam $OUTDIR/accepted_hits.bam -b $OUTDIR/mask.gff > $OUTDIR/tophat_aligned_reads_masked.bam    
    	    
        samtools index $OUTDIR/tophat_aligned_reads_masked.bam
    
        rm $OUTDIR/mask.gff
        
        samtools sort -n $OUTDIR/tophat_aligned_reads_masked.bam $OUTDIR/tophat_aligned_reads_masked_sorted.tmp
        samtools fixmate $OUTDIR/tophat_aligned_reads_masked_sorted.tmp.bam $OUTDIR/tophat_aligned_reads_masked_sorted.bam
        rm $OUTDIR/tophat_aligned_reads_masked_sorted.tmp.bam
    	
        samtools view $OUTDIR/tophat_aligned_reads_masked_sorted.bam -f 3  | htseq-count --quiet $HT_SEQ_OPTIONS - $GENCODEGTF | grep ENSG > $HTOUTDIR/${anno_version}_masked.gene
        # add intersect
        samtools view $OUTDIR/tophat_aligned_reads_masked_sorted.bam -f 3  | htseq-count --quiet --mode intersection-strict $HT_SEQ_OPTIONS - $GENCODEGTF | grep ENSG > $HTOUTDIR/${anno_version}_masked_strict.gene
        samtools view $OUTDIR/tophat_aligned_reads_masked_sorted.bam -f 3  | htseq-count --quiet --mode intersection-nonempty $HT_SEQ_OPTIONS - $GENCODEGTF | grep ENSG > $HTOUTDIR/${anno_version}_masked_nonempty.gene
      
      #  samtools view $OUTDIR/tophat_aligned_reads_masked_sorted.bam  | htseq-count --quiet --idattr="transcript_id" $HT_SEQ_OPTIONS - $GENCODEGTF | grep ENST > $HTOUTDIR/${anno_version}_masked.transcript
    
        echo "[NOTE] calculate RPKMs per Gencode Gene masked"
    
        Rscript --vanilla ${NGSANE_BASE}/tools/CalcGencodeGeneRPKM.R $GENCODEGTF $HTOUTDIR/${anno_version}_masked.gene $RPKMSSDIR/${n/%$READONE.$FASTQ/_gene_masked} ${anno_version}
    
        rm $OUTDIR/tophat_aligned_reads_masked_sorted.bam
    
        rm $OUTDIR/accepted_hits_sorted.bam
    
        #file_arg sample_arg stranded_arg firststrand_arg paired_arg
        Rscript --vanilla ${NGSANE_BASE}/tools/BamToBw.R $OUTDIR/accepted_hits_f3.bam ${n/%$READONE.$FASTQ/}_masked $BAM2BW_OPTION_1 $BIGWIGSDIR $BAM2BW_OPTION_2
    
        # mark checkpoint
        [ -f ${n/%$READONE.$FASTQ/_masked} ] && echo -e "\n********* $CHECKPOINT\n" && unset RECOVERFROM    
    fi

fi

################################################################################
echo ">>>>> enddate "`date`
