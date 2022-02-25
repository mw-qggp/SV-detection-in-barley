#import pandas as pd

configfile: "config.yaml"


FASTA = config["ref"]["fasta"]

#PATH_FASTQ = "/gpfs/project/projects/qggp/Hv-DRR-DNAseq2020/data/Rawdata/"
PATH_FASTQ = "/gpfs/project/projects/qggp/Hv-DRR-DNAseq2020/data/Rawdata/128.120.88.251/X202SC20040457-Z01-F001/raw_data/barley_wildtyp/"

#inputWildcards = glob_wildcards(PATH_FASTQ+"{S}/*.fq.gz")
#SAMPLES = set(inputWildcards.S)
#READ = set(inputWildcards.R)
#NAMES = set(inputWildcards.N)

#SAMPLES = ["Ancap2", "CM67", "Georgie", "HOR12830", "HOR1842", "HOR383", "HOR7985", "HOR8160", "IG128104", "IG31424", "ItuNativ", "K10693", "K10877", "Kharsila", "Kombyne", "Lakhan", "Sanalta", "Sissy", "SpratArc", "Unumli_A", "W23829_8"]
#SAMPLES = ["HvLib012", "HvLib013"]
SAMPLES = ["SRR11456021","SRR11456022","SRR11456027"]

CHROMS = ["chr1H","chr2H","chr3H","chr4H","chr5H","chr6H","chr7H"]

rule all:
	input:
		expand("03_removePCRduplicates/{sample}_sorted_rmdup_rd.bam", sample = SAMPLES),
		expand("04_variantCalling/gatk_SNPs_Indels_{sample}.g.vcf.gz", sample = SAMPLES),
		expand("04_variantCalling/NGSEP2_{sample}_SV.gff", sample = SAMPLES),
		expand("04_variantCalling/gridss_{sample}.bam", sample = SAMPLES),
		expand("04_variantCalling/smoove_{sample}/{sample}-smoove.vcf.gz", sample = SAMPLES),
		expand("04_variantCalling/delly_{sample}.vcf", sample = SAMPLES),
		expand("04_variantCalling/{sample}.mantadir/results/variants/diploidSV.vcf.gz", sample = SAMPLES)
		#chroms einbauen!!!
		#expand final file

module load SamTools BWA HTSlib Java/1.8.0_151 lumpy/0.3.0 sambamba/0.6.6 R/3.5.3 Bowtie2 gcc

PATH="$HOME/bin:$PATH:/gpfs/project/projects/qggp/src/gsort"
export PATH=$PATH:/gpfs/project/projects/qggp/src:$PATH

PATH="$HOME/bin:$PATH:/home/mawei111/.conda/envs/py3/bin/mosdepth"
export PATH=$PATH:/home/mawei111/.conda/envs/py3/bin:mosdepth

cd $PBS_O_WORKDIR

mut_genome="genome_chr1H_it.fa"
sample="trans_it_65cov"
ref="genome_chr1H.fa"

rule simulate_reads:
	input:
		mut_ref="{sample}.fa" ##check correct name

	output:
		out1="{sample}_R1.fastq", ##check correct name
		out2="{sample}_R2.fastq"

	params:
		p_1="true", 
		p_2="40",
		p_3="150", 
		p_4=coverage,
		p_5="350",
		p_6="450",
		p_7="40",
		p_8="35",
		p_9="25"

	shell:
		"/gpfs/project/projects/qggp/src/bbmap/randomreads.sh ref={input.mut_ref} paired={params.p_1} q={params.p_2} length={params.p_3} coverage={params.p_4} mininsert={params.p_5} maxinsert={params.p_6} maxq={params.p_7} midq={params.p_8} minq={params.p_9} out1={output.out1} out2={output.out2}"

rule gzip:
	input:
		f1=rules.simulate_reads.output.out_r1
		f2=rules.simulate_reads.output.out_r2
	output:
		f1="{sample}_R1.fastq.gz"
		f2="{sample}_R2.fastq.gz"
		
	run:
		shell("gzip {input.f1}")
		shell("gzip {input.f2}")


rule trimming:
	input:
		in_r1=PATH_FASTQ+"{sample}/{sample}_1.fq.gz",
		in_r2=PATH_FASTQ+"{sample}/{sample}_2.fq.gz"

	output:
		out_r1_p="01_trimming/{sample}_trimmed_paired_1.fq.gz",
		out_r1_unp="01_trimming/{sample}_trimmed_unpaired_1.fq.gz",
		out_r2_p="01_trimming/{sample}_trimmed_paired_2.fq.gz",
		out_r2_unp="01_trimming/{sample}_trimmed_unpaired_2.fq.gz"
	shell:
		"module load Java/1.8.0_151; java -jar /gpfs/project/projects/qggp/src/Trimmomatic-0.39/trimmomatic-0.39.jar PE -threads 20 {input.in_r1} {input.in_r2} {output.out_r1_p} {output.out_r1_unp} {output.out_r2_p} {output.out_r2_unp} ILLUMINACLIP:TruSeq3-PE.fa:2:30:10 SLIDINGWINDOW:4:15 MINLEN:36"

rule bwa_mapping:
	input:
		ref=FASTA,
		fastq_r1="01_trimming/{sample}_trimmed_paired_1.fq.gz",
		fastq_r2="01_trimming/{sample}_trimmed_paired_2.fq.gz"

	output:
		sam="02_mapping/{sample}.sam"
	shell:
		"module load BWA; bwa mem -t 20 {input.ref} {input.fastq_r1} {input.fastq_r2} >{output.sam}"

rule convert_sam:
	input:
		sam="02_mapping/{sample}.sam"
	output:
		bam="02_mapping/{sample}_sorted.bam",
		bai="02_mapping/{sample}_sorted.bam.bai"
	shell:
		"module load SamTools; samtools view -Sb {input.sam} | samtools sort - >{output.bam}; wait; samtools index {output.bam}"

rule remove_duplicates:
	input:
		bam="02_mapping/{sample}_sorted.bam"
	output:
		bam="03_removePCRduplicates/{sample}_sorted_rmdup.bam",
		txt="03_removePCRduplicates/{sample}_rmdup_metrics.txt"
	shell:
		"module load Java/1.8.0_151; java -jar /gpfs/project/projects/qggp/src/picard_2.22.0/picard.jar MarkDuplicates I={input.bam} O={output.bam} REMOVE_DUPLICATES=true METRICS_FILE={output.txt}"

#########Variant calling programs########

rule manta1:
	input:
		bam="03_removePCRduplicates/{sample}_sorted_rmdup.bam",
		ref=FASTA
	output:
		folder="04_variantCalling/{sample}.mantadir/",
		py="04_variantCalling/{sample}.mantadir/runWorkflow.py"	
	shell:
		"/gpfs/project/projects/qggp/src/manta-1.6.0.centos6_x86_64/bin/configManta.py --bam {input.bam} --referenceFasta {input.ref} --runDir {output.folder}"

rule manta2:
	input:
		py="04_variantCalling/{sample}.mantadir/runWorkflow.py"
	output:
		vcf="04_variantCalling/{sample}.mantadir/results/variants/diploidSV.vcf.gz"
	shell:
		"{input.py} -j 5 -g 5"

rule delly:
	input:
		ref=FASTA,
		bam="03_removePCRduplicates/{sample}_sorted_rmdup.bam"
	output:
		bcf="04_variantCalling/delly_{sample}.bcf"
	shell:
		"/gpfs/project/projects/qggp/src/delly_v0.8.1_linux_x86_64bit call -o {output.bcf} -g {input.ref} {input.bam}"

rule delly2:
	input:
		bcf="04_variantCalling/delly_{sample}.bcf"
	output:
		vcf="04_variantCalling/delly_{sample}.vcf"
	shell:
		"/gpfs/project/projects/qggp/Potatodenovo/src/bcftools-1.10.2/bcftools view {input.bcf} >{output.vcf}"

rule lumpy:
	input:
		bam="03_removePCRduplicates/{sample}_sorted_rmdup.bam",
		ref=FASTA
	output:
		vcf="04_variantCalling/smoove_{sample}/{sample}-smoove.vcf.gz"
	params:
		outdir="04_variantCalling/smoove_{sample}",
		name="{sample}"
	shell:
		"""module load SamTools lumpy/0.3.0; PATH="$HOME/bin:$PATH:/gpfs/project/projects/qggp/src/gsort"; export PATH=$PATH:/gpfs/project/projects/qggp/src:$PATH; PATH="$HOME/bin:$PATH:/home/mawei111/.conda/envs/py3/bin/mosdepth"; export PATH=$PATH:/home/mawei111/.conda/envs/py3/bin:mosdepth; /gpfs/project/projects/qggp/src/smoove call --name {params.name} --fasta {input.ref} --outdir {params.outdir} {input.bam}"""

rule gridss:
	input:
		ref=FASTA,
		bam="03_removePCRduplicates/{sample}_sorted_rmdup.bam"

	output:
		vcf="04_variantCalling/gridss_{sample}.vcf",
		bam="04_variantCalling/gridss_{sample}.bam"
	shell:
		"module load BWA/0.7.15 Java/1.8.0_151 sambamba/0.6.6 R/3.5.3; sh /gpfs/project/projects/qggp/src/gridss-2.6.2/scripts/gridss.sh --output {output.vcf} --threads 4 --reference {input.ref} --assembly {output.bam} --jar /gpfs/project/projects/qggp/src/gridss-2.6.2/scripts/gridss-2.8.3-gridss-jar-with-dependencies.jar --jvmheap 31g {input.bam}"

rule NGSEP2:
	input:
		ref=FASTA,
		bam="03_removePCRduplicates/{sample}_sorted_rmdup.bam"
	output:
		csv="04_variantCalling/NGSEP2_{sample}_SV.gff"
	params:
		csv="04_variantCalling/NGSEP2_{sample}"
	shell:
		"module load Java/1.8.0_151; java -jar /gpfs/project/projects/qggp/src/NGSEPcore_3.3.2.jar FindVariants -ignoreXS -noSNVS -runRD -runRP -maxAlnsPerStartPos 2 -minMQ 0 {input.ref} {input.bam} {params.csv}"

rule addReadgroup:
	input:
		bam="03_removePCRduplicates/{sample}_sorted_rmdup.bam"
	output:
		bamo="03_removePCRduplicates/{sample}_sorted_rmdup_rd.bam"
	shell:
		"module load Java/1.8.0_151 SamTools; java -jar /gpfs/project/projects/qggp/src/picard_2.22.0/picard.jar AddOrReplaceReadGroups I={input.bam} O={output.bamo} RGID=1 RGLB=lib1 RGPL=ILLUMINA RGPU=unit1 RGSM=20; samtools index {output.bamo}"

rule haplotypecaller:
	input:
		ref=FASTA,
		bam="03_removePCRduplicates/{sample}_sorted_rmdup_rd.bam"
	output:
		vcf="04_variantCalling/gatk_SNPs_Indels_{sample}.g.vcf.gz"
	shell:
		"""module load Java/1.8.0_151; /gpfs/project/projects/qggp/src/gatk-4.1.6.0/gatk --java-options "-Xmx10g" HaplotypeCaller -R {input.ref} -I {input.bam} -O {output.vcf} -ERC GVCF"""

#Haplotypecaller in g.vcf-modus benutzen!
