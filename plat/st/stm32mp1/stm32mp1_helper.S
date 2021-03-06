/*
 * Copyright (c) 2015-2018, ARM Limited and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <arch.h>
#include <asm_macros.S>
#include <bl_common.h>
#include <platform_def.h>
#include <stm32_gpio.h>
#include <stm32mp1_rcc.h>

#define GPIO_BANK_G_ADDRESS	0x50008000
#define GPIO_TX_PORT		11
#define GPIO_TX_SHIFT		(GPIO_TX_PORT << 1)
#define GPIO_TX_ALT_SHIFT	((GPIO_TX_PORT - GPIO_ALT_LOWER_LIMIT) << 2)
#define STM32MP1_HSI_CLK	64000000

	.globl	platform_mem_init
	.globl	plat_report_exception
	.globl	plat_get_my_entrypoint
	.globl	plat_secondary_cold_boot_setup
	.globl	plat_reset_handler
	.globl	plat_is_my_cpu_primary
	.globl	plat_my_core_pos
	.globl	plat_crash_console_init
	.globl	plat_crash_console_flush
	.globl	plat_crash_console_putc
	.globl	plat_panic_handler

func platform_mem_init
	/* Nothing to do, don't need to init SYSRAM */
	bx	lr
endfunc platform_mem_init

func plat_report_exception
	bx	lr
endfunc plat_report_exception

func plat_reset_handler
	bx	lr
endfunc plat_reset_handler

	/* ------------------------------------------------------------------
	 * unsigned long plat_get_my_entrypoint (void);
	 *
	 * Main job of this routine is to distinguish between a cold and warm
	 * boot.
	 *
	 * Currently supports only cold boot
	 * ------------------------------------------------------------------
	 */
func plat_get_my_entrypoint
	mov	r0, #0
	bx	lr
endfunc plat_get_my_entrypoint

	/* ---------------------------------------------
	 * void plat_secondary_cold_boot_setup (void);
	 *
	 * Cold-booting secondary CPUs is not supported.
	 * ---------------------------------------------
	 */
func plat_secondary_cold_boot_setup
	b	.
endfunc plat_secondary_cold_boot_setup

	/* -----------------------------------------------------
	 * unsigned int plat_is_my_cpu_primary (void);
	 *
	 * Find out whether the current cpu is the primary cpu.
	 * -----------------------------------------------------
	 */
func plat_is_my_cpu_primary
	ldcopr	r0, MPIDR
	ldr	r1, =(MPIDR_CLUSTER_MASK | MPIDR_CPU_MASK)
	and	r0, r1
	cmp	r0, #STM32MP1_PRIMARY_CPU
	moveq	r0, #1
	movne	r0, #0
	bx	lr
endfunc plat_is_my_cpu_primary

	/* -------------------------------------------
	 *  int plat_stm32mp1_get_core_pos(int mpidr);
	 *
	 *  Return CorePos = (ClusterId * 4) + CoreId
	 * -------------------------------------------
	 */
func plat_stm32mp1_get_core_pos
	and	r1, r0, #MPIDR_CPU_MASK
	and	r0, r0, #MPIDR_CLUSTER_MASK
	add	r0, r1, r0, LSR #6
	bx	lr
endfunc plat_stm32mp1_get_core_pos

	/* ------------------------------------
	 *  unsigned int plat_my_core_pos(void)
	 * ------------------------------------
	 */
func plat_my_core_pos
	ldcopr	r0, MPIDR
	b	plat_stm32mp1_get_core_pos
endfunc plat_my_core_pos

	/* ---------------------------------------------
	 * int plat_crash_console_init(void)
	 *
	 * Initialize the crash console without a C Runtime stack.
	 * ---------------------------------------------
	 */
func plat_crash_console_init
	/* Enable GPIOs for UART4 TX */
	ldr	r1, =(RCC_BASE + RCC_MP_AHB4ENSETR)
	ldr	r2, [r1]
	/* Configure GPIO G11 */
	orr	r2, r2, #RCC_MP_AHB4ENSETR_GPIOGEN
	str	r2, [r1]
	ldr	r1, =GPIO_BANK_G_ADDRESS
	/* Set GPIO mode alternate */
	ldr	r2, [r1, #GPIO_MODE_OFFSET]
	bic	r2, r2, #(GPIO_MODE_MASK << GPIO_TX_SHIFT)
	orr	r2, r2, #(GPIO_MODE_ALTERNATE << GPIO_TX_SHIFT)
	str	r2, [r1, #GPIO_MODE_OFFSET]
	/* Set GPIO speed low */
	ldr	r2, [r1, #GPIO_SPEED_OFFSET]
	bic	r2, r2, #(GPIO_SPEED_MASK << GPIO_TX_SHIFT)
	str	r2, [r1, #GPIO_SPEED_OFFSET]
	/* Set no-pull */
	ldr	r2, [r1, #GPIO_PUPD_OFFSET]
	bic	r2, r2, #(GPIO_PULL_MASK << GPIO_TX_SHIFT)
	str	r2, [r1, #GPIO_PUPD_OFFSET]
	/* Set alternate AF6 */
	ldr	r2, [r1, #GPIO_AFRH_OFFSET]
	bic	r2, r2, #(GPIO_ALTERNATE_MASK << GPIO_TX_ALT_SHIFT)
	orr	r2, r2, #(GPIO_ALTERNATE_6 << GPIO_TX_ALT_SHIFT)
	str	r2, [r1, #GPIO_AFRH_OFFSET]

	/* Enable UART clock, with HSI source */
	ldr	r1, =(RCC_BASE + RCC_UART24CKSELR)
	mov	r2, #RCC_UART24CKSELR_HSI
	str	r2, [r1]
	ldr	r1, =(RCC_BASE + RCC_MP_APB1ENSETR)
	ldr	r2, [r1]
	orr	r2, r2, #RCC_MP_APB1ENSETR_UART4EN
	str	r2, [r1]

	ldr	r0, =STM32MP1_DEBUG_USART_BASE
	ldr	r1, =STM32MP1_HSI_CLK
	ldr	r2, =STM32MP1_UART_BAUDRATE
	b	console_core_init
endfunc plat_crash_console_init

	/* ---------------------------------------------
	 * int plat_crash_console_flush(void)
	 *
	 * Flush the crash console without a C Runtime stack.
	 * ---------------------------------------------
	 */
func plat_crash_console_flush
	ldr	r1, =STM32MP1_DEBUG_USART_BASE
	b	console_core_flush
endfunc plat_crash_console_flush

	/* ---------------------------------------------
	 * int plat_crash_console_putc(int c)
	 *
	 * Print a character on the crash console without a C Runtime stack.
	 * Clobber list : r1 - r3
	 *
	 * In case of bootloading through uart, we keep console crash as this.
	 * Characters could be sent to the programmer, but will be ignored.
	 * No specific code in that case.
	 * ---------------------------------------------
	 */
func plat_crash_console_putc
	ldr	r1, =STM32MP1_DEBUG_USART_BASE
	b	console_core_putc
endfunc plat_crash_console_putc
